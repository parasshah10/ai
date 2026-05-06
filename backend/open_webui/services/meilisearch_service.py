import meilisearch
import os
import logging
from typing import Optional, List, Dict, Any

from open_webui.config import MEILISEARCH_URL, MEILISEARCH_API_KEY

log = logging.getLogger(__name__)

# Global variable to hold the MeiliSearchService instance
meilisearch_service_instance: Optional["MeiliSearchService"] = None

class MeiliSearchService:
    def __init__(self, url: str, api_key: str):
        self.client = meilisearch.Client(url, api_key)
        self.index = self.client.index("messages")
        self.index.update(primary_key='id')
        log.info("MeiliSearch client initialized and primary key set.")

    def setup_index(self):
        """Sets up the index settings."""
        settings = {
            "rankingRules": ["words", "typo", "proximity", "attribute", "sort", "exactness"],
            "searchableAttributes": ["content"],
            "filterableAttributes": ["chatId", "userId", "tags", "folderId", "archived", "pinned", "shared", "role", "timestamp"],
            "sortableAttributes": ["timestamp"],
            "typoTolerance": {
                "enabled": True,
                "minWordSizeForTypos": {
                    "oneTypo": 4,
                    "twoTypos": 8
                }
            }
        }
        self.index.update_settings(settings)
        log.info("MeiliSearch index settings configured - searching content only.")

    def get_branch_path(self, message_id: str, messages_dict: Dict[str, Any]) -> List[str]:
        """Builds an array of message IDs from the root to the given message."""
        path = []
        current_id = message_id
        while current_id:
            path.append(current_id)
            message = messages_dict.get(current_id)
            if not message:
                break
            current_id = message.get("parent")
        path.reverse()
        return path

    def extract_messages_from_chat(self, chat_model) -> List[Dict[str, Any]]:
        """Flatten chat history and prepare messages for indexing."""
        if not chat_model or not chat_model.chat:
            log.warning(f"extract_messages_from_chat: chat_model or chat_model.chat is missing for chat_id {chat_model.id}")
            return []

        messages_dict = chat_model.chat.get("history", {}).get("messages", {})
        if not messages_dict:
            log.warning(f"extract_messages_from_chat: messages_dict is empty for chat_id {chat_model.id}")
            return []

        documents = []
        for message_id, message in messages_dict.items():
            if not message.get("content"):
                continue

            branch_path = self.get_branch_path(message_id, messages_dict)
            
            # Get timestamp and validate it
            msg_timestamp = message.get("timestamp", chat_model.updated_at)
            
            # Auto-correct millisecond timestamps
            if msg_timestamp > 4102444800:
                msg_timestamp = msg_timestamp // 1000

            doc = {
                "id": f"{chat_model.id}-{message_id}",
                "chatId": chat_model.id,
                "messageId": message_id,
                "userId": chat_model.user_id,
                "chatTitle": chat_model.title,
                "content": message["content"],
                "role": message.get("role"),
                "timestamp": msg_timestamp,
                "parentId": message.get("parent"),
                "branchPath": branch_path,
                "tags": chat_model.meta.get("tags", []),
                "folderId": chat_model.folder_id,
                "archived": chat_model.archived,
                "pinned": chat_model.pinned,
                "shared": bool(chat_model.share_id),
            }
            documents.append(doc)
        return documents

    async def index_chat(self, chat_id: str, user_id: str):
        """Indexes a single chat and its messages."""
        from open_webui.models.chats import Chats

        log.info(f"Attempting to index chat_id: {chat_id} for user_id: {user_id}")
        chat_model = await Chats.get_chat_by_id(chat_id)
        if not chat_model:
            log.error(f"index_chat: Chat model with id {chat_id} not found in database.")
            return
        
        if chat_model.user_id != user_id:
            log.error(f"index_chat: User {user_id} does not have access to chat {chat_id}.")
            return

        log.info(f"index_chat: Found chat '{chat_model.title}' for indexing.")
        documents = self.extract_messages_from_chat(chat_model)
        
        if documents:
            log.info(f"index_chat: Extracted {len(documents)} documents to index.")
            log.debug(f"index_chat: Sample document: {documents[0]}")
            task = self.index.add_documents(documents)
            log.info(f"Successfully queued {len(documents)} documents for chat_id: {chat_id} for indexing. Task UID: {task.task_uid}")
        else:
            log.warning(f"index_chat: No documents were extracted from chat_id: {chat_id}")

    async def delete_chat_from_index(self, chat_id: str):
        """Deletes all messages of a chat from the index."""
        log.info(f"Attempting to delete chat_id: {chat_id} from index")
        try:
            # Search for all documents with this chatId and delete them by ID
            # We need to fetch all documents, so use a high limit
            search_results = self.index.search("", {
                "filter": f'chatId = "{chat_id}"',
                "limit": 10000,
                "attributesToRetrieve": ["id"]
            })
            
            doc_ids = [hit["id"] for hit in search_results.get("hits", [])]
            
            if doc_ids:
                log.info(f"Found {len(doc_ids)} documents to delete for chat_id: {chat_id}")
                self.index.delete_documents(doc_ids)
                log.info(f"Successfully queued deletion of {len(doc_ids)} documents for chat_id: {chat_id}")
            else:
                log.info(f"No documents found for chat_id: {chat_id}")
        except Exception as e:
            log.error(f"Failed to delete chat {chat_id} from index: {e}")

    async def delete_message_from_index(self, chat_id: str, message_id: str):
        """Deletes a specific message from the index."""
        doc_id = f"{chat_id}-{message_id}"
        log.info(f"Attempting to delete message document: {doc_id} from index")
        try:
            self.index.delete_document(doc_id)
            log.info(f"Successfully queued deletion for document: {doc_id}")
        except Exception as e:
            log.error(f"Failed to delete message document {doc_id}: {e}")

    async def delete_messages_from_index(self, chat_id: str, message_ids: list[str]):
        """Deletes multiple messages from the index."""
        if not message_ids:
            return
        doc_ids = [f"{chat_id}-{msg_id}" for msg_id in message_ids]
        log.info(f"Attempting to delete {len(doc_ids)} message documents from index")
        try:
            self.index.delete_documents(doc_ids)
            log.info(f"Successfully queued deletion for {len(doc_ids)} documents")
        except Exception as e:
            log.error(f"Failed to delete message documents: {e}")

    async def search_messages(
        self,
        query: str,
        user_id: str,
        chat_id: Optional[str] = None,
        page: int = 1,
        limit: int = 60,
        sort_by: str = "relevance",
        filters: Dict[str, Any] = None
    ) -> Dict[str, Any]:
        """Searches for messages with security filters and sorting."""
        search_params = {
            "limit": limit,
            "offset": (page - 1) * limit,
            "attributesToHighlight": ["content"],
            "highlightPreTag": "<mark>",
            "highlightPostTag": "</mark>",
            "showMatchesPosition": True,
            "showRankingScore": True,
        }

        # Build filter conditions
        filter_conditions = [f'userId = "{user_id}"']
        
        if chat_id:
            filter_conditions.append(f'chatId = "{chat_id}"')
        
        if filters:
            if filters.get('role'):
                filter_conditions.append(f"role = {filters['role']}")
            
            if filters.get('timestamp_gte'):
                filter_conditions.append(f"timestamp >= {filters['timestamp_gte']}")
            
            if filters.get('tags'):
                tag_filters = " OR ".join([f"tags = {tag}" for tag in filters['tags']])
                filter_conditions.append(f"({tag_filters})")
            
            if filters.get('folder_id'):
                filter_conditions.append(f"folderId = {filters['folder_id']}")

        search_params["filter"] = " AND ".join(filter_conditions)
        results = self.index.search(query, search_params)
        
        # Client-side sort by date if requested
        if sort_by == "date" and results.get('hits'):
            results['hits'] = sorted(results['hits'], key=lambda x: x.get('timestamp', 0), reverse=True)
        
        return results

    async def reindex_all_chats_for_user(self, user_id: str):
        """Re-indexes all chats for a specific user, removing orphaned documents."""
        from open_webui.models.chats import Chats
        
        log.info(f"Re-indexing all chats for user {user_id}")
        
        # Step 1: Delete all existing documents for this user to ensure clean sync
        log.info(f"Deleting all existing documents for user {user_id}")
        deleted_total = 0
        try:
            # Paginate through deletions to handle large datasets efficiently
            batch_size = 10000
            offset = 0
            
            while True:
                search_results = self.index.search("", {
                    "filter": f'userId = "{user_id}"',
                    "limit": batch_size,
                    "offset": offset,
                    "attributesToRetrieve": ["id"]
                })
                
                old_doc_ids = [hit["id"] for hit in search_results.get("hits", [])]
                
                if not old_doc_ids:
                    break  # No more documents to delete
                
                self.index.delete_documents(old_doc_ids)
                deleted_total += len(old_doc_ids)
                log.info(f"Deleted batch of {len(old_doc_ids)} documents (total: {deleted_total})")
                
                # If we got fewer results than batch_size, we're done
                if len(old_doc_ids) < batch_size:
                    break
                    
            if deleted_total > 0:
                log.info(f"Successfully queued deletion of {deleted_total} old documents for user {user_id}")
            else:
                log.info(f"No existing documents found for user {user_id}")
        except Exception as e:
            log.error(f"Failed to delete existing documents for user {user_id}: {e}")
        
        # Step 2: Re-index all current chats
        all_user_chats = await Chats.get_chats_by_user_id(user_id)
        
        total_chats = len(all_user_chats)
        indexed_count = 0
        
        for chat in all_user_chats:
            try:
                await self.index_chat(chat.id, chat.user_id)
                indexed_count += 1
                log.info(f"Indexed chat {chat.id} ({indexed_count}/{total_chats})")
            except Exception as e:
                log.error(f"Failed to index chat {chat.id}: {e}")
        
        log.info(f"Re-indexing complete: deleted {deleted_total} old documents, indexed {indexed_count}/{total_chats} chats")
        return {"total": total_chats, "indexed": indexed_count, "deleted": deleted_total}
    
    def parse_query_with_filters(self, raw_query: str) -> (str, Dict[str, Any]):
        """Parses special syntax like tag: and folder: from the query."""
        # TODO: Implement query parsing
        return raw_query, {}


def initialize_meilisearch_service():
    """Initializes the MeiliSearch service and sets up the index."""
    global meilisearch_service_instance
    if MEILISEARCH_URL and MEILISEARCH_API_KEY:
        try:
            meilisearch_service_instance = MeiliSearchService(url=MEILISEARCH_URL, api_key=MEILISEARCH_API_KEY)
            meilisearch_service_instance.setup_index()
            log.info("MeiliSearch service initialized successfully.")
        except Exception as e:
            log.error(f"Failed to initialize MeiliSearch service: {e}")
            meilisearch_service_instance = None
    else:
        log.warning("MeiliSearch URL or API key not configured. Search will be disabled.")

def shutdown_meilisearch_service():
    """Placeholder for any shutdown logic."""
    global meilisearch_service_instance
    meilisearch_service_instance = None
    log.info("MeiliSearch service shut down.")

def get_meilisearch_service() -> Optional[MeiliSearchService]:
    """Returns the singleton instance of the MeiliSearch service."""
    return meilisearch_service_instance
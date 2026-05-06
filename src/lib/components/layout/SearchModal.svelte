<script lang="ts">
	import { toast } from 'svelte-sonner';
	import { getContext, onDestroy, onMount, tick } from 'svelte';
	const i18n = getContext('i18n');

	import Modal from '$lib/components/common/Modal.svelte';
	import SearchInput from './Sidebar/SearchInput.svelte';
	import {
		getChatById,
		getChatList,
		getChatListBySearchText,
		searchMessages,
		reindexUserChats,
		type MessageSearchResult
	} from '$lib/apis/chats';
	import Spinner from '../common/Spinner.svelte';

	import dayjs from '$lib/dayjs';
	import localizedFormat from 'dayjs/plugin/localizedFormat';
	import calendar from 'dayjs/plugin/calendar';
	import Loader from '../common/Loader.svelte';
	import { createMessagesList } from '$lib/utils';
	import { config, user } from '$lib/stores';
	import Messages from '../chat/Messages.svelte';
	import { goto } from '$app/navigation';
	import PencilSquare from '../icons/PencilSquare.svelte';
	import PageEdit from '../icons/PageEdit.svelte';
	dayjs.extend(calendar);
	dayjs.extend(localizedFormat);

	export let show = false;
	export let onClose = () => {};

	let actions = [
		{
			label: $i18n.t('Start a new conversation'),
			onClick: async () => {
				await goto(`/${query ? `?q=${query}` : ''}`);
				show = false;
				onClose();
			},
			icon: PencilSquare
		}
	];

	let query = '';
	let page = 1;

	let searchType = 'message'; // 'message' or 'chat' - default to message

	let chatList = null;
	let messageSearchResponse: SearchResponse | null = null;

	let chatListLoading = false;
	let allChatsLoaded = false;

	let searchDebounceTimeout;

	let selectedIdx = null;
	let selectedChat = null;

	let selectedModels = [''];
	let history = null;
	let messages = null;

	// Search controls
	let searchMode = 'smart'; // 'smart', 'exact', 'advanced'
	let sortBy = 'relevance'; // 'relevance', 'date'
	let groupByConversation = false;
	let showFilters = false;
	let showPreview = false; // Preview toggle - default off
	
	// Filters
	let dateFilter = 'all'; // 'all', 'today', 'week', 'month', 'custom'
	let roleFilter = 'all'; // 'all', 'user', 'assistant'
	let selectedTags = [];
	let selectedFolder = null;

	// Reindex state
	let isReindexing = false;
	let reindexProgress = { indexed: 0, total: 0 };

	// Pagination for message results
	let messageResultsPage = 1;
	const RESULTS_PER_PAGE = 10;
	$: displayedMessageResults = messageSearchResponse?.hits.slice(0, messageResultsPage * RESULTS_PER_PAGE) || [];
	$: hasMoreResults = messageSearchResponse && displayedMessageResults.length < messageSearchResponse.hits.length;

	$: if (!chatListLoading && chatList) {
		loadChatPreview(selectedIdx);
	}

	const loadChatPreview = async (selectedIdx) => {
		if (!chatList || chatList.length === 0 || selectedIdx === null) {
			selectedChat = null;
			messages = null;
			history = null;
			selectedModels = [''];
			return;
		}

		const selectedChatIdx = selectedIdx - actions.length;
		if (selectedChatIdx < 0 || selectedChatIdx >= chatList.length) {
			selectedChat = null;
			messages = null;
			history = null;
			selectedModels = [''];
			return;
		}

		const chatId = chatList[selectedChatIdx].id;

		const chat = await getChatById(localStorage.token, chatId).catch(async (error) => {
			return null;
		});

		if (chat) {
			if (chat?.chat?.history) {
				selectedModels =
					(chat?.chat?.models ?? undefined) !== undefined
						? chat?.chat?.models
						: [chat?.chat?.models ?? ''];

				history = chat?.chat?.history;
				messages = createMessagesList(chat?.chat?.history, chat?.chat?.history?.currentId);

				// scroll to the bottom of the messages container
				await tick();
				const messagesContainerElement = document.getElementById('chat-preview');
				if (messagesContainerElement) {
					messagesContainerElement.scrollTop = messagesContainerElement.scrollHeight;
				}
			} else {
				messages = [];
			}
		} else {
			toast.error($i18n.t('Failed to load chat preview'));
			selectedChat = null;
			messages = null;
			history = null;
			selectedModels = [''];
			return;
		}
	};

	const loadMessageChatPreview = async (chatId, messageId) => {
		const chat = await getChatById(localStorage.token, chatId).catch(async (error) => {
			return null;
		});

		if (chat) {
			if (chat?.chat?.history) {
				selectedModels =
					(chat?.chat?.models ?? undefined) !== undefined
						? chat?.chat?.models
						: [chat?.chat?.models ?? ''];

				selectedChat = chat;
				
				// Find the leaf of the branch containing the message
				let leafId = messageId;
				const messagesDict = chat.chat.history.messages;
				while (messagesDict[leafId]?.childrenIds?.length > 0) {
					leafId = messagesDict[leafId].childrenIds.at(-1);
				}

				history = {
					...chat.chat.history,
					currentId: leafId
				};
				messages = createMessagesList(history, leafId);

				// Scroll to the target message
				await tick();
				const messagesContainerElement = document.getElementById('chat-preview');
				if (messagesContainerElement) {
					// Try to find and scroll to the specific message
					setTimeout(() => {
						const messageElement = messagesContainerElement.querySelector(`#message-${messageId}`);
						if (messageElement) {
							messageElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
						} else {
							messagesContainerElement.scrollTop = messagesContainerElement.scrollHeight;
						}
					}, 100);
				}
			} else {
				messages = [];
			}
		}
	};

	const searchHandler = async () => {
		if (!show) {
			return;
		}

		if (searchDebounceTimeout) {
			clearTimeout(searchDebounceTimeout);
		}

		page = 1;
		chatList = null;
		messageSearchResponse = null;
		chatListLoading = true;

		if (query === '') {
			if (searchType === 'chat') {
				chatList = await getChatList(localStorage.token, page);
			} else {
				// For message search with empty query, just show empty state
				messageSearchResponse = { hits: [], totalHits: 0, processingTimeMs: 0, page: 1, limit: 60, query: '' };
			}
			chatListLoading = false;
		} else {
			if (searchDebounceTimeout) {
				clearTimeout(searchDebounceTimeout);
			}

			searchDebounceTimeout = setTimeout(async () => {
				if (searchType === 'chat') {
					chatList = await getChatListBySearchText(localStorage.token, query, page);
				} else {
					// Reset pagination
					messageResultsPage = 1;

					// Build filter parameters
					let filters = {};
					if (roleFilter !== 'all') {
						filters.role = roleFilter;
					}
					if (dateFilter !== 'all') {
						const now = Math.floor(Date.now() / 1000);
						const dayInSeconds = 86400;
						let timestampFilter;
						if (dateFilter === 'today') {
							timestampFilter = now - dayInSeconds;
						} else if (dateFilter === 'week') {
							timestampFilter = now - (7 * dayInSeconds);
						} else if (dateFilter === 'month') {
							timestampFilter = now - (30 * dayInSeconds);
						}
						if (timestampFilter) {
							filters.timestamp = Math.floor(timestampFilter);
						}
					}
					if (selectedTags.length > 0) {
						filters.tags = selectedTags;
					}
					if (selectedFolder) {
						filters.folderId = selectedFolder;
					}

					// Modify query for exact match mode
					let searchQuery = query;
					if (searchMode === 'exact') {
						searchQuery = `"${query}"`;
					}

					// Fetch ALL results from backend
					messageSearchResponse = await searchMessages(
						localStorage.token,
						searchQuery,
						page,
						sortBy,
						filters
					).catch((e) => {
						console.error('Message search failed:', e);
						return null;
					});
				}

				if ((chatList ?? []).length === 0) {
					allChatsLoaded = true;
				} else {
					allChatsLoaded = false;
				}
				chatListLoading = false;
			}, 300);
		}

		selectedChat = null;
		messages = null;
		history = null;
		selectedModels = [''];

		if ((chatList ?? []).length === 0) {
			allChatsLoaded = true;
		} else {
			allChatsLoaded = false;
		}
	};

	const loadMoreChats = async () => {
		chatListLoading = true;
		page += 1;

		let newChatList = [];

		if (query) {
			newChatList = await getChatListBySearchText(localStorage.token, query, page);
		} else {
			newChatList = await getChatList(localStorage.token, page);
		}

		// once the bottom of the list has been reached (no results) there is no need to continue querying
		allChatsLoaded = newChatList.length === 0;

		if (newChatList.length > 0) {
			const existingIds = new Set(chatList.map((c) => c.id));
			const uniqueNewChats = newChatList.filter((c) => !existingIds.has(c.id));
			chatList = [...chatList, ...uniqueNewChats];
		}

		chatListLoading = false;
	};

	$: if (show) {
		searchHandler();
	}

	const onKeyDown = (e) => {
		const searchOptions = document.getElementById('search-options-container');
		if (searchOptions || !show) {
			return;
		}

		if (e.code === 'Escape') {
			show = false;
			onClose();
		} else if (e.code === 'Enter') {
			const item = document.querySelector(`[data-arrow-selected="true"]`);
			if (item) {
				item?.click();
				show = false;
			}

			return;
		} else if (e.code === 'ArrowDown') {
			const searchInput = document.getElementById('search-input');

			if (searchInput) {
				// check if focused on the search input
				if (document.activeElement === searchInput) {
					searchInput.blur();
					selectedIdx = 0;
					return;
				}
			}

			selectedIdx = Math.min(selectedIdx + 1, (chatList ?? []).length - 1 + actions.length);
		} else if (e.code === 'ArrowUp') {
			if (selectedIdx === 0) {
				const searchInput = document.getElementById('search-input');

				if (searchInput) {
					// check if focused on the search input
					if (document.activeElement !== searchInput) {
						searchInput.focus();
						selectedIdx = 0;
						return;
					}
				}
			}

			selectedIdx = Math.max(selectedIdx - 1, 0);
		}

		const item = document.querySelector(`[data-arrow-selected="true"]`);
		item?.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
	};

	onMount(() => {
		actions = [
			...actions,
			...(($config?.features?.enable_notes ?? false) &&
			($user?.role === 'admin' || ($user?.permissions?.features?.notes ?? true))
				? [
						{
							label: $i18n.t('Create a new note'),
							onClick: async () => {
								await goto(`/notes?content=${query}`);
								show = false;
								onClose();
							},
							icon: PageEdit
						}
					]
				: [])
		];

		document.addEventListener('keydown', onKeyDown);
	});

	onDestroy(() => {
		if (searchDebounceTimeout) {
			clearTimeout(searchDebounceTimeout);
		}
		document.removeEventListener('keydown', onKeyDown);
	});

	const handleReindex = async () => {
		isReindexing = true;
		reindexProgress = { indexed: 0, total: 0 };

		try {
			const result = await reindexUserChats(localStorage.token);
			reindexProgress = result;
			toast.success($i18n.t(`Re-indexed ${result.indexed} out of ${result.total} chats successfully`));
			
			// Refresh search results
			await searchHandler();
		} catch (e) {
			toast.error($i18n.t('Failed to re-index chats: {{error}}', { error: e.message || e }));
		} finally {
			isReindexing = false;
		}
	};
</script>

<Modal size="xl" bind:show>
	<div class="py-3 dark:text-gray-300 text-gray-700">
		<div class="px-4 pb-1.5">
			<div class="flex items-center justify-center mb-2 text-sm">
				<button
					class="px-3 py-1 rounded-l-lg {searchType === 'message'
						? 'bg-gray-200 dark:bg-gray-700'
						: 'bg-gray-100 dark:bg-gray-800'}"
					on:click={() => {
						searchType = 'message';
						searchHandler();
					}}
				>
					{$i18n.t('Messages')}
				</button>
				<button
					class="px-3 py-1 rounded-r-lg {searchType === 'chat'
						? 'bg-gray-200 dark:bg-gray-700'
						: 'bg-gray-100 dark:bg-gray-800'}"
					on:click={() => {
						searchType = 'chat';
						searchHandler();
					}}
				>
					{$i18n.t('Chats')}
				</button>
			</div>

			{#if searchType === 'message'}
				<!-- Compact filter controls -->
				<div class="flex items-center gap-2 mb-2 text-xs flex-wrap">
					<!-- Search Mode Toggle -->
					<div class="flex rounded-md overflow-hidden border border-gray-200 dark:border-gray-700">
						<button
							class="px-2 py-1 {searchMode === 'smart'
								? 'bg-blue-500 text-white'
								: 'bg-gray-50 dark:bg-gray-800'}"
							on:click={() => {
								searchMode = 'smart';
								searchHandler();
							}}
						>
							Smart
						</button>
						<button
							class="px-2 py-1 {searchMode === 'exact'
								? 'bg-blue-500 text-white'
								: 'bg-gray-50 dark:bg-gray-800'}"
							on:click={() => {
								searchMode = 'exact';
								searchHandler();
							}}
						>
							Exact
						</button>
					</div>

					<!-- Sort Toggle -->
					<div class="flex rounded-md overflow-hidden border border-gray-200 dark:border-gray-700">
						<button
							class="px-2 py-1 {sortBy === 'relevance'
								? 'bg-blue-500 text-white'
								: 'bg-gray-50 dark:bg-gray-800'}"
							on:click={() => {
								sortBy = 'relevance';
								searchHandler();
							}}
						>
							Relevance
						</button>
						<button
							class="px-2 py-1 {sortBy === 'date'
								? 'bg-blue-500 text-white'
								: 'bg-gray-50 dark:bg-gray-800'}"
							on:click={() => {
								sortBy = 'date';
								searchHandler();
							}}
						>
							Date
						</button>
					</div>

					<!-- Group Toggle -->
					<button
						class="px-2 py-1 rounded-md border border-gray-200 dark:border-gray-700 {groupByConversation
							? 'bg-blue-500 text-white'
							: 'bg-gray-50 dark:bg-gray-800'}"
						on:click={() => {
							groupByConversation = !groupByConversation;
						}}
					>
						Group
					</button>

					<!-- Filters Toggle -->
					<button
						class="px-2 py-1 rounded-md border border-gray-200 dark:border-gray-700 {showFilters
							? 'bg-blue-500 text-white'
							: 'bg-gray-50 dark:bg-gray-800'}"
						on:click={() => {
							showFilters = !showFilters;
						}}
					>
						Filters {showFilters ? '▼' : '▶'}
					</button>

					<!-- Preview Toggle -->
					<button
						class="px-2 py-1 rounded-md border border-gray-200 dark:border-gray-700 {showPreview
							? 'bg-blue-500 text-white'
							: 'bg-gray-50 dark:bg-gray-800'}"
						on:click={() => {
							showPreview = !showPreview;
						}}
					>
						Preview
					</button>

					<!-- Reindex Button -->
					<button
						class="px-2 py-1 rounded-md border border-gray-200 dark:border-gray-700 bg-orange-500 text-white hover:bg-orange-600 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1"
						on:click={handleReindex}
						disabled={isReindexing}
						title="Re-index all your chats to update search"
					>
						{#if isReindexing}
							<Spinner className="size-3" />
							{reindexProgress.indexed}/{reindexProgress.total}
						{:else}
							⟳ Re-index
						{/if}
					</button>
				</div>

				{#if showFilters}
					<div class="p-2 bg-gray-50 dark:bg-gray-850 rounded-md mb-2 text-xs space-y-2">
						<!-- Date Filter -->
						<div class="flex items-center gap-2">
							<label class="text-gray-600 dark:text-gray-400 min-w-[60px]">Date:</label>
							<select
								bind:value={dateFilter}
								on:change={searchHandler}
								class="flex-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded px-2 py-1"
							>
								<option value="all">All Time</option>
								<option value="today">Today</option>
								<option value="week">Last 7 Days</option>
								<option value="month">Last 30 Days</option>
							</select>
						</div>

						<!-- Role Filter -->
						<div class="flex items-center gap-2">
							<label class="text-gray-600 dark:text-gray-400 min-w-[60px]">Role:</label>
							<select
								bind:value={roleFilter}
								on:change={searchHandler}
								class="flex-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded px-2 py-1"
							>
								<option value="all">All Messages</option>
								<option value="user">User Only</option>
								<option value="assistant">AI Only</option>
							</select>
						</div>
					</div>
				{/if}
			{/if}

			<SearchInput
				bind:value={query}
				on:input={searchHandler}
				placeholder={$i18n.t('Search')}
				showClearButton={true}
				onFocus={() => {
					selectedIdx = null;
					messages = null;
				}}
				onKeydown={(e) => {
					console.log('e', e);

					if (e.code === 'Enter' && (chatList ?? []).length > 0) {
						const item = document.querySelector(`[data-arrow-selected="true"]`);
						if (item) {
							item?.click();
						}

						show = false;
						return;
					} else if (e.code === 'ArrowDown') {
						selectedIdx = Math.min(selectedIdx + 1, (chatList ?? []).length - 1 + actions.length);
					} else if (e.code === 'ArrowUp') {
						selectedIdx = Math.max(selectedIdx - 1, 0);
					} else {
						selectedIdx = 0;
					}

					const item = document.querySelector(`[data-arrow-selected="true"]`);
					item?.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
				}}
			/>
		</div>

		<!-- <hr class="border-gray-50 dark:border-gray-850/30 my-1" /> -->

		<div class="flex px-4 pb-1">
			<div
				class="flex flex-col overflow-y-auto h-96 md:h-[40rem] max-h-full scrollbar-hidden w-full flex-1 pr-2"
			>
				<div class="w-full text-xs text-gray-500 dark:text-gray-500 font-medium pb-2 px-2">
					{$i18n.t('Actions')}
				</div>

				{#each actions as action, idx (action.label)}
					<button
						class=" w-full flex items-center rounded-xl text-sm py-2 px-3 hover:bg-gray-50 dark:hover:bg-gray-850 {selectedIdx ===
						idx
							? 'bg-gray-50 dark:bg-gray-850'
							: ''}"
						data-arrow-selected={selectedIdx === idx ? 'true' : undefined}
						dragabble="false"
						on:mouseenter={() => {
							selectedIdx = idx;
						}}
						on:click={async () => {
							await action.onClick();
						}}
					>
						<div class="pr-2">
							<svelte:component this={action.icon} />
						</div>
						<div class=" flex-1 text-left">
							<div class="text-ellipsis line-clamp-1 w-full">
								{$i18n.t(action.label)}
							</div>
						</div>
					</button>
				{/each}

				{#if searchType === 'chat'}
					{#if chatList}
						<hr class="border-gray-50 dark:border-gray-850/30 my-3" />

						{#if chatList.length === 0}
							<div class="text-xs text-gray-500 dark:text-gray-400 text-center px-5 py-4">
								{$i18n.t('No results found')}
							</div>
						{/if}

						{#each chatList as chat, idx (chat.id)}
						{#if idx === 0 || (idx > 0 && chat.time_range !== chatList[idx - 1].time_range)}
							<div
								class="w-full text-xs text-gray-500 dark:text-gray-500 font-medium {idx === 0
									? ''
									: 'pt-5'} pb-2 px-2"
							>
								{$i18n.t(chat.time_range)}
								<!-- localisation keys for time_range to be recognized from the i18next parser (so they don't get automatically removed):
							{$i18n.t('Today')}
							{$i18n.t('Yesterday')}
							{$i18n.t('Previous 7 days')}
							{$i18n.t('Previous 30 days')}
							{$i18n.t('January')}
							{$i18n.t('February')}
							{$i18n.t('March')}
							{$i18n.t('April')}
							{$i18n.t('May')}
							{$i18n.t('June')}
							{$i18n.t('July')}
							{$i18n.t('August')}
							{$i18n.t('September')}
							{$i18n.t('October')}
							{$i18n.t('November')}
							{$i18n.t('December')}
							-->
							</div>
						{/if}

							<a
								class=" w-full flex justify-between items-center rounded-xl text-sm py-2 px-3 hover:bg-gray-50 dark:hover:bg-gray-850 {selectedIdx ===
								idx + actions.length
									? 'bg-gray-50 dark:bg-gray-850'
									: ''}"
								href="/c/{chat.id}"
								draggable="false"
								data-arrow-selected={selectedIdx === idx + actions.length ? 'true' : undefined}
								on:mouseenter={() => {
									selectedIdx = idx + actions.length;
								}}
								on:click={async () => {
									await goto(`/c/${chat.id}`);
									show = false;
									onClose();
								}}
							>
								<div class=" flex-1">
									<div class="text-ellipsis line-clamp-1 w-full">
										{chat?.title}
									</div>
								</div>

							<div class=" pl-3 shrink-0 text-gray-500 dark:text-gray-400 text-xs">
								{$i18n.t(
									dayjs(chat?.updated_at * 1000).calendar(null, {
										sameDay: '[Today]',
										nextDay: '[Tomorrow]',
										nextWeek: 'dddd',
										lastDay: '[Yesterday]',
										lastWeek: '[Last] dddd',
										sameElse: 'L' // use localized format, otherwise dayjs.calendar() defaults to DD/MM/YYYY
									})
								)}
							</div>
						</a>
					{/each}

					{#if !allChatsLoaded}
						<Loader
							on:visible={(e) => {
								if (!chatListLoading) {
									loadMoreChats();
								}
							}}
						>
							<div class="w-full flex justify-center py-4 text-xs animate-pulse items-center gap-2">
								<Spinner className=" size-4" />
								<div class=" ">{$i18n.t('Loading...')}</div>
							</div>
						</Loader>
					{/if}
				{:else}
					<div class="w-full h-full flex justify-center items-center">
						<Spinner className="size-5" />
					</div>
				{/if}
			{:else if searchType === 'message'}
				{#if messageSearchResponse}
					<hr class="border-gray-50 dark:border-gray-850 my-3" />

					{#if messageSearchResponse.hits.length === 0}
						<div class="text-xs text-gray-500 dark:text-gray-400 text-center px-5 py-4">
							{$i18n.t('No results found')}
						</div>
					{:else}
						<div
							class="w-full text-xs text-gray-500 dark:text-gray-500 font-medium pb-2 px-2 flex justify-between items-center"
						>
								<span class="font-semibold">Message Results</span>
								<span class="text-gray-600 dark:text-gray-400">
									<span class="font-semibold text-gray-700 dark:text-gray-300">{messageSearchResponse.estimatedTotalHits || messageSearchResponse.totalHits}</span>
									{messageSearchResponse.estimatedTotalHits ? ' ~' : ''} hits in
									<span class="font-semibold text-gray-700 dark:text-gray-300">{messageSearchResponse.processingTimeMs}</span>ms
								</span>
							</div>

							{#if groupByConversation}
								{@const groupedResults = displayedMessageResults.reduce((groups, item) => {
									const key = item.chatId;
									if (!groups[key]) {
										groups[key] = {
											chatId: key,
											chatTitle: item.chatTitle || 'Untitled Chat',
											messages: []
										};
									}
									groups[key].messages.push(item);
									return groups;
								}, {})}
								
								{@const groupsSortedByFirstMessage = Object.values(groupedResults).sort((a, b) => {
									// When sorting by date, use the timestamp; otherwise use score
									// Groups are ordered by their first message (backend already sorted)
									const firstA = a.messages[0];
									const firstB = b.messages[0];
									
									if (sortBy === 'date') {
										return firstB.timestamp - firstA.timestamp; // Newest first
									}
									return firstB._rankingScore - firstA._rankingScore; // Best match first
								})}
	
								{#each groupsSortedByFirstMessage as group (group.chatId)}
									<!-- Don't re-sort messages - trust backend order -->
									{@const sortedMessages = group.messages}
									
									<div class="mb-3">
										<div class="text-xs font-semibold text-gray-700 dark:text-gray-300 px-2 py-1 bg-gray-100 dark:bg-gray-800 rounded-t-lg">
											{group.chatTitle} <span class="text-gray-500">({group.messages.length})</span>
										</div>
										{#each sortedMessages as item (item.id)}
											<a
												class="w-full block text-sm py-2 px-3 border-l-2 border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-850 hover:border-blue-500"
												href="/c/{item.chatId}?mid={item.messageId}"
												on:mouseenter={() => {
													selectedIdx = item.id;
													if (showPreview) {
														loadMessageChatPreview(item.chatId, item.messageId);
													}
												}}
												on:click={() => {
													show = false;
													onClose();
												}}
												data-arrow-selected={selectedIdx === item.id ? 'true' : undefined}
											>
												<div class="text-ellipsis line-clamp-2 w-full font-medium text-gray-700 dark:text-gray-300 message-highlight"
												     style="white-space: pre-wrap; word-break: break-word;">
													{@html item._formatted?.content || ''}
												</div>
												<div class="text-xs text-gray-500 mt-0.5 flex justify-between items-center">
													<span>{item.role === 'user' ? 'You' : 'AI'} • {new Date(item.timestamp * 1000).toLocaleDateString()}</span>
													<span>Score: {item._rankingScore.toFixed(2)}</span>
												</div>
											</a>
										{/each}
									</div>
								{/each}
							{:else}
								{#each displayedMessageResults as item, idx (item.id)}
									<a
										class="w-full block rounded-xl text-sm py-2 px-3 my-1 border border-gray-200 dark:border-gray-800 hover:bg-gray-50 dark:hover:bg-gray-850 hover:border-blue-500"
										href="/c/{item.chatId}?mid={item.messageId}"
										on:mouseenter={() => {
											selectedIdx = actions.length + idx;
											if (showPreview) {
												loadMessageChatPreview(item.chatId, item.messageId);
											}
										}}
										on:click={() => {
											show = false;
											onClose();
										}}
										data-arrow-selected={selectedIdx === actions.length + idx ? 'true' : undefined}
									>
										<div class="text-xs text-gray-500 mb-1">{item.chatTitle || 'Untitled Chat'}</div>
										<div class="text-ellipsis line-clamp-2 w-full font-medium text-gray-700 dark:text-gray-300 message-highlight"
										     style="white-space: pre-wrap; word-break: break-word;">
											{@html item._formatted?.content || ''}
										</div>
										<div class="text-xs text-gray-500 mt-1 flex justify-between items-center">
											<span>{item.role === 'user' ? 'You' : 'AI'} • {new Date(item.timestamp * 1000).toLocaleDateString()}</span>
											<span>Score: {item._rankingScore.toFixed(2)}</span>
										</div>
									</a>
								{/each}
	
								{#if hasMoreResults}
									<button
										class="w-full text-center py-3 text-sm text-blue-500 hover:bg-gray-50 dark:hover:bg-gray-850 rounded-lg"
										on:click={() => {
											messageResultsPage += 1;
										}}
									>
										Load More ({messageSearchResponse.hits.length - displayedMessageResults.length} remaining)
									</button>
								{/if}
							{/if}
						{/if}
					{:else}
						<div class="w-full h-full flex justify-center items-center">
							<Spinner className="size-5" />
						</div>
					{/if}
				{/if}
			</div>
			<div
				id="chat-preview"
				class="{showPreview ? 'md:flex' : 'hidden'} md:flex-1 w-full overflow-y-auto h-96 md:h-[40rem] scrollbar-hidden @container"
			>
				{#if messages === null}
					<div
						class="w-full h-full flex justify-center items-center text-gray-500 dark:text-gray-400 text-sm"
					>
						{$i18n.t('Select a conversation to preview')}
					</div>
				{:else}
					<div class="w-full h-full flex flex-col">
						<Messages
							className="h-full flex pt-4 pb-8 w-full"
							chatId={`chat-preview-${selectedChat?.id ?? ''}`}
							user={$user}
							readOnly={true}
							{selectedModels}
							bind:history
							bind:messages
							autoScroll={true}
							sendMessage={() => {}}
							continueResponse={() => {}}
							regenerateResponse={() => {}}
						/>
					</div>
				{/if}
			</div>
		</div>
	</div>
</Modal>

<style>
	:global(.message-highlight mark) {
		background: rgba(59, 130, 246, 0.2) !important;
		color: inherit;
		padding: 2px 4px;
		border-radius: 2px;
		font-weight: 600;
	}
</style>

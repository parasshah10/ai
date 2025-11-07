<script lang="ts">
    import { createEventDispatcher} from 'svelte';
    import Modal from '../common/Modal.svelte';
    import { toast } from 'svelte-sonner';
    const dispatch = createEventDispatcher();
    
    export let show = false;
    let textInput = '';

    const basicTemplate = "### USER\n\n\n### ASSISTANT\n";

    function parseMessages(text: string) {
        const messages = [];
        const sections = text.split(/(?=### (?:USER|ASSISTANT))/);
        
        for (const section of sections) {
            if (!section.trim()) continue;
            
            const match = section.match(/### (USER|ASSISTANT)\s*([\s\S]*?)(?=(?:### (?:USER|ASSISTANT))|$)/);
            if (match) {
                const [_, role, content] = match;
                messages.push({
                    role: role.toLowerCase(),
                    content: content.trim()
                });
            }
        }
        
        return messages;
    }

    function handleSubmit() {
        const messages = parseMessages(textInput);
        if (messages.length === 0) {
            toast.error('No valid messages found');
            return;
        }
        dispatch('submit', { messages });
        show = false;
        textInput = '';
    }

    function insertTemplate() {
        textInput = textInput ? `${textInput}\n\n${basicTemplate}` : basicTemplate;
    }

    $: if (show) {
        textInput = '';
    }
</script>

<Modal bind:show size="md">
    <div class="text-gray-700 dark:text-gray-100">
        <div class="flex justify-between dark:text-gray-300 px-5 pt-4 pb-1">
            <div class="text-lg font-medium self-center">Import Messages</div>
            <div class="flex gap-2">
                <button
                    class="text-sm px-3 py-1.5 text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 rounded border border-gray-300 dark:border-gray-600"
                    on:click={insertTemplate}
                >
                    Insert Template
                </button>
                <button
                    class="self-center"
                    on:click={() => {
                        show = false;
                    }}
                >
                    <svg
                        xmlns="http://www.w3.org/2000/svg"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                        class="w-5 h-5"
                    >
                        <path
                            d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z"
                        />
                    </svg>
                </button>
            </div>
        </div>

        <div class="p-4">
            <textarea
                class="w-full h-64 p-3 border rounded-lg bg-white dark:bg-gray-800 dark:border-gray-700 dark:text-gray-100"
                placeholder={"### USER\nHello\n\n### ASSISTANT\nHello! How can I help you today?"}
                bind:value={textInput}
            />
            <div class="flex justify-end gap-2 mt-4">
                <button
                    class="px-4 py-2 text-gray-600 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 rounded"
                    on:click={() => show = false}
                >
                    Cancel
                </button>
                <button
                    class="px-4 py-2 text-white bg-gray-900 dark:bg-gray-700 rounded hover:bg-gray-800 dark:hover:bg-gray-600"
                    on:click={handleSubmit}
                >
                    Import
                </button>
            </div>
        </div>
    </div>
</Modal>
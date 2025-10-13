<script lang="ts">
  import { onMount, onDestroy, tick } from 'svelte';

  export let history: {
    messages: Record<string, any>;
    currentId: string | null;
  };
  export let messagesContainerElement: HTMLDivElement | null = null;

  // UI state
  let open = false;

  // Active/hover state
  let activeMessageId: string | null = null;
  let hoveredMessageId: string | null = null;

  // Observers and handlers
  let observer: IntersectionObserver | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let onScroll: (() => void) | null = null;

  // Linearized path messages (root -> currentId)
  let messages: any[] = [];

  // For vertical centering of minimap relative to the messages container
  let minimapTop = 0;

  // Per-role offsets to clear the navbar fade/gradient area
  const AI_TOP_OFFSET = 40;
  const USER_TOP_OFFSET = 25;

  function getTopOffsetForMessage(m: any): number {
    return m?.role === 'user' ? USER_TOP_OFFSET : AI_TOP_OFFSET;
  }

  // Build the linear path from root -> currentId (used for stable ordering in minimap)
  $: {
    const list: any[] = [];
    if (history?.currentId && history?.messages) {
      let currentId = history.currentId;
      while (currentId !== null) {
        const msg = history.messages[currentId];
        if (msg) {
          list.unshift(msg);
          currentId = msg.parentId;
        } else {
          break;
        }
      }
    }
    messages = list;

    // Initialize highlight on first render
    if (!activeMessageId && messages.length > 0) {
      activeMessageId = messages[0].id;
    }

    // If we already have an observer (late path changes), re-attach
    if (observer) {
      tick().then(() => updateObserver());
    }
  }

  onMount(() => {
    if (messagesContainerElement) {
      setupObserverAndHandlers();
    }
    updateMinimapTop();
    window.addEventListener('resize', updateMinimapTop);
  });

  // Late binding: messagesContainerElement becomes available after mount
  $: if (!observer && messagesContainerElement) {
    setupObserverAndHandlers();
    updateMinimapTop();
  }

  function setupObserverAndHandlers() {
    if (!messagesContainerElement) return;

    observer = new IntersectionObserver(
      // Use tripwire-based active detection for stability
      () => {
        updateActiveByTripwire();
      },
      {
        root: messagesContainerElement,
        rootMargin: '0px 0px -99% 0px',
        threshold: 0
      }
    );

    updateObserver();
    setupResizeObserver();

    // Prime highlight and centering after first paint
    requestAnimationFrame(() => {
      updateActiveByTripwire();
      updateMinimapTop();
    });

    const handler = () => {
      updateActiveByTripwire();
      updateMinimapTop();
    };

    onScroll = handler;
    messagesContainerElement.addEventListener('scroll', handler, { passive: true });
    messagesContainerElement.addEventListener('wheel', handler, { passive: true });
  }

  function setupResizeObserver() {
    if (resizeObserver) resizeObserver.disconnect();
    if (messagesContainerElement && 'ResizeObserver' in window) {
      resizeObserver = new ResizeObserver(() => updateMinimapTop());
      resizeObserver.observe(messagesContainerElement);
    }
  }

  function updateMinimapTop() {
    if (!messagesContainerElement) return;
    const r = messagesContainerElement.getBoundingClientRect();
    minimapTop = Math.round(r.top + r.height / 2);
  }

  function updateObserver() {
    if (!observer) return;
    observer.disconnect();
    for (const msg of messages) {
      const el = document.getElementById(`message-${msg.id}`);
      if (el) observer.observe(el);
    }
  }

  // TOP TRIPWIRE LOGIC (with per-role offsets):
  // Active = the last message whose top has crossed the container top + per-role offset.
  function updateActiveByTripwire() {
    if (!messagesContainerElement) return;

    const containerTop = messagesContainerElement.getBoundingClientRect().top;
    let chosenId: string | null = null;

    for (const m of messages) {
      const el = document.getElementById(`message-${m.id}`);
      if (!el) continue;

      const top = el.getBoundingClientRect().top;
      const offset = getTopOffsetForMessage(m);
      if (top <= containerTop + offset + 1) {
        // keep advancing until we exceed the offset tripwire
        chosenId = m.id;
      } else {
        // list is in order; once below the offset tripwire, stop
        break;
      }
    }

    if (!chosenId && messages.length > 0) {
      // If nothing has crossed the offset yet, pick the first message in the path
      chosenId = messages[0].id;
    }

    if (chosenId) {
      activeMessageId = chosenId;
    }
  }

  function scrollToMessage(messageId: string) {
    const element = document.getElementById(`message-${messageId}`);
    if (element && messagesContainerElement) {
      const containerRect = messagesContainerElement.getBoundingClientRect();
      const elementRect = element.getBoundingClientRect();

      const m = messages.find((mm) => mm.id === messageId);
      const offset = getTopOffsetForMessage(m);

      const delta = elementRect.top - containerRect.top - offset;

      // Immediate visual feedback
      activeMessageId = messageId;

      messagesContainerElement.scrollTo({
        top: messagesContainerElement.scrollTop + delta,
        behavior: 'smooth'
      });
    }
  }

  function navigatePrevious() {
    // Sync with current viewport position
    updateActiveByTripwire();

    let idx = messages.findIndex((m) => m.id === activeMessageId);
    if (idx === -1) idx = 0;

    if (idx > 0) {
      scrollToMessage(messages[idx - 1].id);
    }
  }

  function navigateNext() {
    // Sync with current viewport position
    updateActiveByTripwire();

    let idx = messages.findIndex((m) => m.id === activeMessageId);
    if (idx === -1) idx = 0;

    if (idx >= 0 && idx < messages.length - 1) {
      scrollToMessage(messages[idx + 1].id);
    }
  }

  onDestroy(() => {
    if (onScroll && messagesContainerElement) {
      messagesContainerElement.removeEventListener('scroll', onScroll as unknown as EventListener);
      messagesContainerElement.removeEventListener('wheel', onScroll as unknown as EventListener);
    }
    window.removeEventListener('resize', updateMinimapTop);
    resizeObserver?.disconnect();
    observer?.disconnect();
  });
</script>

{#if messages.length > 2}
  <!-- Mobile slide-in minimap, vertically centered relative to messages container -->
  <div
    class="fixed right-0 z-30 md:hidden"
    style="top: {minimapTop}px; transform: translateY(-50%);"
    role="navigation"
    aria-label="Chat conversation minimap"
  >
    {#if !open}
      <!-- Closed: thin handle with 44x44 tap target -->
      <button
        type="button"
        class="w-11 h-11 flex items-center justify-end pr-1 rounded-l-full focus:outline-none focus:ring-2 focus:ring-gray-400"
        on:click={() => (open = true)}
        aria-label="Open minimap"
      >
        <span class="w-1.5 h-10 rounded-full bg-gray-300 dark:bg-gray-600"></span>
      </button>
    {:else}
      <!-- Open: compact rail with close button in corner -->
      <div class="w-14 flex flex-col items-center gap-2 p-1 rounded-l-xl bg-white/80 dark:bg-gray-900/80 backdrop-blur-sm shadow border-l border-t border-b border-gray-100 dark:border-gray-800 relative">
        <!-- Close button (top-right corner) -->
        <button
          type="button"
          class="absolute -top-1 -right-1 p-0.5 rounded-full bg-gray-200 dark:bg-gray-700 hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
          on:click={() => (open = false)}
          aria-label="Close minimap"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2.5"
            stroke="currentColor"
            class="w-3 h-3"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </button>

        <!-- Previous button -->
        <button
          type="button"
          class="p-1 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors disabled:opacity-40 mt-4"
          on:click={navigatePrevious}
          disabled={messages.findIndex((m) => m.id === activeMessageId) <= 0}
          aria-disabled={messages.findIndex((m) => m.id === activeMessageId) <= 0}
          aria-label="Previous message"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-3 h-3"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 15.75l7.5-7.5 7.5 7.5" />
          </svg>
        </button>

        <!-- Markers -->
        <div class="relative flex flex-col items-center gap-2 py-1 overflow-hidden">
          {#each messages as message (message.id)}
            {@const isUser = message.role === 'user'}
            {@const isActive = message.id === activeMessageId}
            {@const markerClasses = isUser ? 'w-2 h-0.5' : 'w-4 h-1'}
            {@const colorClasses = isActive
              ? 'bg-gray-900 dark:bg-gray-100'
              : 'bg-gray-400 dark:bg-gray-400'}

            <button
              type="button"
              class="rounded-full transition-all duration-200 cursor-pointer {markerClasses} {colorClasses}"
              on:click={() => scrollToMessage(message.id)}
              aria-label="Navigate to {isUser ? 'user' : 'AI'} message"
              aria-current={isActive}
            />
          {/each}
        </div>

        <!-- Next button -->
        <button
          type="button"
          class="p-1 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors disabled:opacity-40"
          on:click={navigateNext}
          disabled={messages.findIndex((m) => m.id === activeMessageId) >= messages.length - 1}
          aria-disabled={messages.findIndex((m) => m.id === activeMessageId) >= messages.length - 1}
          aria-label="Next message"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
            class="w-3 h-3"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25l-7.5 7.5-7.5-7.5" />
          </svg>
        </button>
      </div>
    {/if}
  </div>
{/if}
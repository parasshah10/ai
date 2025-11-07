<script lang="ts">
	import { onMount, onDestroy, tick } from 'svelte';
	import { mobile } from '$lib/stores';
	import Tooltip from '$lib/components/common/Tooltip.svelte';
	import { removeAllDetails } from '$lib/utils';

	export let history: {
		messages: Record<string, any>;
		currentId: string | null;
	};
	export let messagesContainerElement: HTMLDivElement | null = null;
	export let messagesComponent: any = null;

	let activeMessageId: string | null = null;
	let hoveredMessageId: string | null = null;
	let observer: IntersectionObserver | null = null;
	let messages: any[] = [];
	let onScroll: (() => void) | null = null;

	// Flag to suppress tripwire updates during programmatic scrolls for instant feedback
	let suppressTripwireUpdate = false;
	let tripwireSuppressionTimeout: ReturnType<typeof setTimeout> | null = null;

	// Markers container for scrollable overflow
	let markersContainerElement: HTMLDivElement | null = null;

	// Per-role top offsets to clear the navbar gradient/fade area
	const AI_TOP_OFFSET = 40;
	const USER_TOP_OFFSET = 25;

	function getTopOffsetForMessage(m: any): number {
		return m?.role === 'user' ? USER_TOP_OFFSET : AI_TOP_OFFSET;
	}

	// For vertical centering of minimap in the chat area
	let minimapTop = 0;
	let resizeObserver: ResizeObserver | null = null;

	// Build the linear path from root -> currentId (used for stable indexing/spacing)
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

	// Auto-center active marker in minimap when it changes
	$: if (activeMessageId && markersContainerElement) {
		centerActiveMarkerInMinimap();
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
			// Defer to our deterministic top-tripwire detector
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

	// TOP TRIPWIRE LOGIC (reverted as requested):
	// Active = the last message whose top has crossed the container top (closest to the top).
	function updateActiveByTripwire() {
		if (!messagesContainerElement) return;
		
		// Skip updates during programmatic scrolls for instant feedback
		if (suppressTripwireUpdate) return;

		const containerTop = messagesContainerElement.getBoundingClientRect().top;
		let chosenId: string | null = null;

		for (const m of messages) {
			const el = document.getElementById(`message-${m.id}`);
			if (!el) continue;

			const top = el.getBoundingClientRect().top;
			const offset = getTopOffsetForMessage(m);
			// Shift tripwire down by a per-role offset to match scroll positioning
			if (top <= containerTop + offset + 1) {
				// keep advancing until we exceed the offset tripwire
				chosenId = m.id;
			} else {
				// list is in order; once a message top is below offset tripwire, stop
				break;
			}
		}

		if (!chosenId && messages.length > 0) {
			// If nothing has crossed top yet, pick the first message in the path
			chosenId = messages[0].id;
		}

		if (chosenId) {
			activeMessageId = chosenId;
		}
	}

	// Center the active marker in the minimap's scrollable container
	function centerActiveMarkerInMinimap() {
		if (!markersContainerElement || !activeMessageId) return;

		const activeButton = markersContainerElement.querySelector(
			`[data-marker-id="${activeMessageId}"]`
		) as HTMLElement;

		if (activeButton) {
			const containerHeight = markersContainerElement.clientHeight;
			const buttonTop = activeButton.offsetTop;
			const buttonHeight = activeButton.offsetHeight;

			// Scroll to center the active marker
			const scrollTo = buttonTop - containerHeight / 2 + buttonHeight / 2;

			markersContainerElement.scrollTo({
				top: scrollTo,
				behavior: 'smooth'
			});
		}
	}

	async function scrollToMessage(messageId: string) {
		const messageIndex = messages.findIndex((m) => m.id === messageId);
		if (messageIndex === -1) return;

		let element = document.getElementById(`message-${messageId}`);
		
		// If element doesn't exist, load required messages
		if (!element && messagesComponent) {
			const requiredCount = messages.length - messageIndex + 5;
			await messagesComponent.loadMessagesToCount(requiredCount);
			await tick();
			element = document.getElementById(`message-${messageId}`);
		}

		if (element && messagesContainerElement) {
			const containerRect = messagesContainerElement.getBoundingClientRect();
			const elementRect = element.getBoundingClientRect();
			
			// Offset to clear the navbar gradient/fade area (per-role)
			const m = messages.find((mm) => mm.id === messageId);
			const offset = getTopOffsetForMessage(m);
			const delta = elementRect.top - containerRect.top - offset;

			// Immediate visual feedback - set active marker before scrolling
			activeMessageId = messageId;

			// Suppress tripwire updates during smooth scroll for instant feedback
			suppressTripwireUpdate = true;
			if (tripwireSuppressionTimeout) {
				clearTimeout(tripwireSuppressionTimeout);
			}

			messagesContainerElement.scrollTo({
				top: messagesContainerElement.scrollTop + delta,
				behavior: 'smooth'
			});

			// Re-enable tripwire after smooth scroll completes (~800ms)
			tripwireSuppressionTimeout = setTimeout(() => {
				suppressTripwireUpdate = false;
				tripwireSuppressionTimeout = null;
			}, 800);
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

	function getPreviewText(content: string): string {
		if (!content) return '';
		// Remove any <details> blocks (e.g., reasoning, tool_calls) before generating preview
		const stripped = removeAllDetails(content);
		const text = stripped.replace(/<[^>]*>/g, '').trim();
		return text.length > 160 ? text.substring(0, 160) + '...' : text;
	}

	onDestroy(() => {
		if (onScroll && messagesContainerElement) {
			messagesContainerElement.removeEventListener('scroll', onScroll as unknown as EventListener);
			messagesContainerElement.removeEventListener('wheel', onScroll as unknown as EventListener);
		}
		window.removeEventListener('resize', updateMinimapTop);
		resizeObserver?.disconnect();
		observer?.disconnect();
		if (tripwireSuppressionTimeout) {
			clearTimeout(tripwireSuppressionTimeout);
		}
	});
</script>

{#if messages.length > 2 && !$mobile}
	<!-- Vertically centered to chat area (computed midpoint of messages container) -->
	<div
		class="hidden md:flex fixed right-3 w-6 flex-col items-center z-20"
		style="top: {minimapTop}px; transform: translateY(-50%);"
		role="navigation"
		aria-label="Chat conversation minimap"
	>
		<!-- Previous button -->
		<button
			type="button"
			class="p-1 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors disabled:opacity-40"
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

		<!-- Markers (scrollable with max-height and fade indicators) -->
		<div
			bind:this={markersContainerElement}
			class="relative flex flex-col items-center gap-0.5 py-1 overflow-y-auto scrollbar-thin scrollbar-thumb-gray-300 dark:scrollbar-thumb-gray-600 scrollbar-track-transparent"
			style="max-height: min(60vh, 500px); mask-image: linear-gradient(to bottom, transparent 0%, black 8px, black calc(100% - 8px), transparent 100%);"
		>
			{#each messages as message (message.id)}
				{@const isUser = message.role === 'user'}
				{@const isActive = message.id === activeMessageId}
				{@const isHovered = message.id === hoveredMessageId}
				{@const markerClasses = isUser ? 'w-2 h-0.5' : 'w-4 h-1'}
				{@const colorClasses = isActive
					? 'bg-gray-900 dark:bg-gray-100'
					: isHovered
						? 'bg-gray-500 dark:bg-gray-500'
						: 'bg-gray-400 dark:bg-gray-400'}

				<Tooltip content="<span style='font-weight:600;font-size:0.8125rem'>{isUser ? 'You' : 'AI'}</span><br/>{getPreviewText(message.content)}" placement="left">
					<button
						type="button"
						class="min-w-[1.5rem] p-1 rounded-md transition-all duration-200 cursor-pointer hover:bg-gray-100/20 dark:hover:bg-gray-800/20 flex items-center justify-center"
						data-marker-id={message.id}
						on:click={() => scrollToMessage(message.id)}
						on:mouseenter={() => (hoveredMessageId = message.id)}
						on:mouseleave={() => (hoveredMessageId = null)}
						aria-label="Navigate to {isUser ? 'user' : 'AI'} message"
						aria-current={isActive}
					>
						<div class="rounded-full {markerClasses} {colorClasses}"></div>
					</button>
				</Tooltip>
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
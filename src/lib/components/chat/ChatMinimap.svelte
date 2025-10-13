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

	let activeMessageId: string | null = null;
	let hoveredMessageId: string | null = null;
	let observer: IntersectionObserver | null = null;
	let messages: any[] = [];
	let onScroll: (() => void) | null = null;

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

	function scrollToMessage(messageId: string) {
		const element = document.getElementById(`message-${messageId}`);
		if (element && messagesContainerElement) {
			const containerRect = messagesContainerElement.getBoundingClientRect();
			const elementRect = element.getBoundingClientRect();
			
			// Offset to clear the navbar gradient/fade area (per-role)
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

	function getPreviewText(content: string): string {
		if (!content) return '';
		// Remove any <details> blocks (e.g., reasoning, tool_calls) before generating preview
		const stripped = removeAllDetails(content);
		const text = stripped.replace(/<[^>]*>/g, '').trim();
		return text.length > 50 ? text.substring(0, 50) + '...' : text;
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

		<!-- Markers -->
		<div class="relative flex flex-col items-center gap-2 py-1">
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

				<Tooltip content="{isUser ? 'You' : 'AI'}<br/>{getPreviewText(message.content)}" placement="left">
					<button
						type="button"
						class="rounded-full transition-all duration-200 cursor-pointer {markerClasses} {colorClasses}"
						on:click={() => scrollToMessage(message.id)}
						on:mouseenter={() => (hoveredMessageId = message.id)}
						on:mouseleave={() => (hoveredMessageId = null)}
						aria-label="Navigate to {isUser ? 'user' : 'AI'} message"
						aria-current={isActive}
					/>
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
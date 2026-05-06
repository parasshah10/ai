<script>
	// Diagnostic, dual-parser Markdown renderer with extensive logging
	// - Uses unified/remark (LibreChat stack) for large content (threshold-controlled)
	// - Falls back to marked (existing pipeline) and compares bare vs with-extensions where possible

	import { onDestroy, onMount, tick } from 'svelte';
	import { marked, Marked } from 'marked';
	import { replaceTokens, processResponseContent } from '$lib/utils';
	import { user } from '$lib/stores';

	import markedExtension from '$lib/utils/marked/extension';
	import markedKatexExtension from '$lib/utils/marked/katex-extension';
	import { disableSingleTilde } from '$lib/utils/marked/strikethrough-extension';
	import { mentionExtension } from '$lib/utils/marked/mention-extension';
	import colonFenceExtension from '$lib/utils/marked/colon-fence-extension';
	import { parseMarkdownToTokens } from '$lib/utils/markdown/unified-parser';

	import MarkdownTokens from './Markdown/MarkdownTokens.svelte';
	import footnoteExtension from '$lib/utils/marked/footnote-extension';
	import citationExtension from '$lib/utils/marked/citation-extension';

	export let id = '';
	export let role = 'assistant'; // Default to assistant
	export let content;
	export let done = true;
	export let model = null;
	export let save = false;
	export let preview = false;

	export let paragraphTag = 'p';
	export let editCodeBlock = true;
	export let topPadding = false;

	export let sourceIds = [];

	export let onSave = () => {};
	export let onUpdate = () => {};

	export let onPreview = () => {};

	export let onSourceClick = () => {};
	export let onTaskClick = () => {};

	let tokens = [];
	let rendering = false;
	let pendingContent = '';

	const options = {
		throwOnError: false,
		breaks: true
	};

	// Configure production marked instance with extensions (current behavior)
	marked.use(markedKatexExtension(options));
	marked.use(markedExtension(options));
	marked.use(citationExtension(options));
	marked.use(footnoteExtension(options));
	marked.use(colonFenceExtension(options));
	marked.use(disableSingleTilde);
	marked.use({
		extensions: [
			mentionExtension({ triggerChar: '@' }),
			mentionExtension({ triggerChar: '#' }),
			mentionExtension({ triggerChar: '$' })
		]
	});

const USE_UNIFIED_PARSER = true;

const renderMarkdown = () => {
	if (rendering) return;
	rendering = true;

	requestAnimationFrame(() => {
		const contentToRender = pendingContent;
		if (contentToRender === null || typeof contentToRender === 'undefined') {
			rendering = false;
			return;
		}

		const msg = String(contentToRender ?? '');
		const processedContent = processResponseContent(msg);
		const contentWithReplacedTokens = replaceTokens(
			processedContent,
			sourceIds,
			model?.name,
			$user?.name
		);

		if (role === 'user') {
			tokens = [
				{
					type: 'paragraph',
					raw: contentWithReplacedTokens,
					text: contentWithReplacedTokens,
					tokens: [{ type: 'text', raw: contentWithReplacedTokens, text: contentWithReplacedTokens }]
				}
			];
		} else {
			tokens = marked.lexer(contentWithReplacedTokens);
		}

		rendering = false;

		if (pendingContent !== contentToRender) {
			renderMarkdown();
		}
	});
};

$: {
	if (content !== pendingContent) {
		pendingContent = content;
		if (!done) {
			// Fast path for streaming: render as plain text
			tokens = [
				{
					type: 'paragraph',
					raw: content,
					text: content,
					tokens: [{ type: 'text', raw: content, text: content }]
				}
			];
		} else {
			renderMarkdown();
		}
	}
}

$: if (done) {
	renderMarkdown();
}
</script>

{#key id}
	<MarkdownTokens
		{tokens}
		{id}
		{done}
		{save}
		{preview}
		{paragraphTag}
		{editCodeBlock}
		{sourceIds}
		{topPadding}
		{onTaskClick}
		{onSourceClick}
		{onSave}
		{onUpdate}
		{onPreview}
	/>
{/key}

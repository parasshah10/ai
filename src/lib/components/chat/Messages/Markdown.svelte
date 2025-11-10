<script>
	// Diagnostic, dual-parser Markdown renderer with extensive logging
	// - Uses unified/remark (LibreChat stack) for large content (threshold-controlled)
	// - Falls back to marked (existing pipeline) and compares bare vs with-extensions where possible

	import { marked, Marked } from 'marked';
	import { replaceTokens, processResponseContent } from '$lib/utils';
	import { user } from '$lib/stores';

	import markedExtension from '$lib/utils/marked/extension';
	import markedKatexExtension from '$lib/utils/marked/katex-extension';
	import { mentionExtension } from '$lib/utils/marked/mention-extension';
	import { parseMarkdownToTokens } from '$lib/utils/markdown/unified-parser';

	import MarkdownTokens from './Markdown/MarkdownTokens.svelte';

	export let id = '';
	export let role = 'assistant'; // Default to assistant
	export let content;
	export let done = true;
	export let model = null;
	export let save = false;
	export let preview = false;

	export let editCodeBlock = true;
	export let topPadding = false;

	export let sourceIds = [];

	export let onSave = () => {};
	export let onUpdate = () => {};

	export let onPreview = () => {};

	export let onSourceClick = () => {};
	export let onTaskClick = () => {};

	let tokens = [];

	const options = {
		throwOnError: false,
		breaks: true
	};

	// Configure production marked instance with extensions (current behavior)
	marked.use(markedKatexExtension(options));
	marked.use(markedExtension(options));
	marked.use({
		extensions: [mentionExtension({ triggerChar: '@' }), mentionExtension({ triggerChar: '#' })]
	});

	const USE_UNIFIED_PARSER = true;

	$: (async () => {
		if (!content && content !== '') return;

		const msg = String(content ?? '');
		const processedContent = processResponseContent(msg);
		const contentWithReplacedTokens = replaceTokens(
			processedContent,
			sourceIds,
			model?.name,
			$user?.name
		);

		// To re-enable markdown rendering for user messages, remove the "if (role === 'user')" block
		// below and uncomment the original parser selection logic that has been commented out.
		/*
		if (USE_UNIFIED_PARSER && role === 'user') {
			const useHybrid = role === 'user';
			const unifiedResult = parseMarkdownToTokens(contentWithReplacedTokens, id, useHybrid);
			if (unifiedResult.success) {
				tokens = unifiedResult.tokens;
			} else {
				// Fallback to marked parser
				tokens = marked.lexer(contentWithReplacedTokens);
			}
		} else {
			tokens = marked.lexer(contentWithReplacedTokens);
		}
		*/

		// Markdown rendering is disabled for user messages. The original content is rendered as plain text.
		if (role === 'user') {
			// Create a simple token structure to render raw text.
			tokens = [
				{
					type: 'paragraph',
					raw: contentWithReplacedTokens,
					text: contentWithReplacedTokens,
					tokens: [{ type: 'text', raw: contentWithReplacedTokens, text: contentWithReplacedTokens }]
				}
			];
		} else {
			// For AI messages, use the marked parser.
			tokens = marked.lexer(contentWithReplacedTokens);
		}
	})();
</script>

{#key id}
	<MarkdownTokens
		{tokens}
		{id}
		{done}
		{save}
		{preview}
		{editCodeBlock}
		{topPadding}
		{onTaskClick}
		{onSourceClick}
		{onSave}
		{onUpdate}
		{onPreview}
	/>
{/key}

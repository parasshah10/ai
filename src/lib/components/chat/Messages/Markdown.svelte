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
		const messageLength = msg.length;
		const timestamp = new Date().toISOString();

		// Header
		console.log(`\n\n`);
		console.log(`╔═══════════════════════════════════════════════════════════════════════════╗`);
		console.log(`║                     MARKDOWN PROCESSING START                              ║`);
		console.log(`╚═══════════════════════════════════════════════════════════════════════════╝`);
		console.log(`[MARKDOWN] Timestamp: ${timestamp}`);
		console.log(`[MARKDOWN] Message ID: ${id}`);
		console.log(`[MARKDOWN] Content length: ${messageLength.toLocaleString()} characters`);
		try {
			console.log(`[MARKDOWN] Content lines: ${msg.split('\n').length}`);
		} catch {
			console.log(`[MARKDOWN] Content lines: n/a`);
		}
		console.log(
			`[MARKDOWN] First 200 chars: "${msg.substring(0, 200).replace(/\n/g, '\\n')}${
				messageLength > 200 ? '...' : ''
			}"`
		);
		console.log(`[MARKDOWN] Role: ${role}`);
		console.log(`[MARKDOWN] Unified parser enabled: ${USE_UNIFIED_PARSER}`);

		const startTime = performance.now();
		const performanceMarks = {};

		// Phase 1: Pre-processing
		console.log(`\n[MARKDOWN] ─────────────────────────────────────────────────────`);
		console.log(`[MARKDOWN] Phase 1: Pre-processing`);
		console.log(`[MARKDOWN] ─────────────────────────────────────────────────────`);

		const processStart = performance.now();
		const processedContent = processResponseContent(msg);
		const processEnd = performance.now();
		performanceMarks.preprocess = processEnd - processStart;

		console.log(`[MARKDOWN] processResponseContent: ${performanceMarks.preprocess.toFixed(2)}ms`);
		console.log(`[MARKDOWN] Content changed: ${processedContent !== msg ? 'YES' : 'NO'}`);
		if (processedContent !== msg) {
			console.log(`[MARKDOWN] Length after processing: ${processedContent.length}`);
		}

		const replaceStart = performance.now();
		const contentWithReplacedTokens = replaceTokens(
			processedContent,
			sourceIds,
			model?.name,
			$user?.name
		);
		const replaceEnd = performance.now();
		performanceMarks.replaceTokens = replaceEnd - replaceStart;

		console.log(`[MARKDOWN] replaceTokens: ${performanceMarks.replaceTokens.toFixed(2)}ms`);
		console.log(
			`[MARKDOWN] Tokens replaced: ${
				processedContent !== contentWithReplacedTokens ? 'YES' : 'NO'
			}`
		);
		console.log(
			`[MARKDOWN] Final content length: ${contentWithReplacedTokens.length.toLocaleString()} chars`
		);

		let parserUsed = 'unknown';
		let parserMetrics = {};
		let fallbackUsed = false;

		// Phase 2: Parser selection
		console.log(`\n[MARKDOWN] ─────────────────────────────────────────────────────`);
		console.log(`[MARKDOWN] Phase 2: Parser Selection & Execution`);
		console.log(`[MARKDOWN] ─────────────────────────────────────────────────────`);

		if (USE_UNIFIED_PARSER && role === 'user') {
			console.log(`[MARKDOWN] Strategy: UNIFIED parser (user message with hybrid optimization)`);
			console.log(`[MARKDOWN] This is the same parser family LibreChat uses (remark-parse)`);

			const unifiedStart = performance.now();
			const useHybrid = role === 'user';
			const unifiedResult = parseMarkdownToTokens(contentWithReplacedTokens, id, useHybrid);
			const unifiedEnd = performance.now();

			if (unifiedResult.success) {
				tokens = unifiedResult.tokens;
				parserUsed = 'unified (remark-parse)';
				parserMetrics = {
					...unifiedResult.metrics,
					totalWallTime: unifiedEnd - unifiedStart
				};

				console.log(`[MARKDOWN] ✓ UNIFIED parser succeeded`);
				console.log(`[MARKDOWN] Wall clock time: ${parserMetrics.totalWallTime.toFixed(2)}ms`);
				console.log(
					`[MARKDOWN] Internal reported time: ${parserMetrics.totalTime.toFixed(2)}ms`
				);
				console.log(`[MARKDOWN] Tokens generated: ${parserMetrics.tokenCount}`);
				console.log(`[MARKDOWN] AST nodes processed: ${parserMetrics.nodeCount}`);
			} else {
				console.error(`[MARKDOWN] ✗ UNIFIED parser FAILED`);
				console.error(`[MARKDOWN] Error: ${unifiedResult.error?.message}`);
				console.error(`[MARKDOWN] Will fallback to marked parser`);
				fallbackUsed = true;
			}
		} else {
			console.log(`[MARKDOWN] Strategy: MARKED parser (AI message)`);
		}

		// Marked parser comparative analysis (bare vs with extensions) if needed or as baseline
		let bareTime = undefined;
		if (parserUsed === 'unknown' || fallbackUsed) {
			console.log(`\n[MARKDOWN] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
			console.log(`[MARKDOWN] Running MARKED parser comparative analysis`);
			console.log(`[MARKDOWN] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);

			// Test 1: Bare marked (no custom extensions)
			try {
				console.log(`[MARKDOWN] Test 1: Bare Marked() instance (no extensions)`);
				const bareMarked = new Marked();
				const bareStart = performance.now();
				// Note: In Marked v9+, instances support .lexer() for tokenization
				const bareTokens = bareMarked.lexer(contentWithReplacedTokens);
				const bareEnd = performance.now();
				bareTime = bareEnd - bareStart;

				console.log(`[MARKDOWN] ✓ Bare marked: ${bareTime.toFixed(2)}ms`);
				console.log(`[MARKDOWN] Tokens: ${bareTokens?.length ?? 0}`);
				console.log(
					`[MARKDOWN] Performance: ${(
						contentWithReplacedTokens.length / Math.max(bareTime, 0.0001)
					).toFixed(0)} chars/ms`
				);
			} catch (e) {
				console.warn(
					`[MARKDOWN] ! Bare Marked instance path not supported in this build: ${e?.message}`
				);
			}

			// Test 2: Marked with extensions (current production)
			console.log(`\n[MARKDOWN] Test 2: Marked (current) with extensions`);
			const extStart = performance.now();
			try {
				tokens = marked.lexer(contentWithReplacedTokens);
				const extEnd = performance.now();
				const extTime = extEnd - extStart;

				console.log(`[MARKDOWN] ✓ Marked+extensions: ${extTime.toFixed(2)}ms`);
				console.log(`[MARKDOWN] Tokens: ${tokens.length}`);
				console.log(
					`[MARKDOWN] Performance: ${(
						contentWithReplacedTokens.length / Math.max(extTime, 0.0001)
					).toFixed(0)} chars/ms`
				);

				if (bareTime !== undefined) {
					const extensionOverhead = extTime - bareTime;
					const overheadPercent =
						bareTime > 0 ? ((extensionOverhead / bareTime) * 100).toFixed(1) : '∞';

					console.log(`\n[MARKDOWN] Extension Overhead Analysis:`);
					console.log(`[MARKDOWN] Bare marked: ${bareTime.toFixed(2)}ms`);
					console.log(`[MARKDOWN] With extensions: ${extTime.toFixed(2)}ms`);
					console.log(`[MARKDOWN] Overhead: ${extensionOverhead.toFixed(2)}ms (+${overheadPercent}%)`);

					if (extensionOverhead > 100) {
						console.warn(`[MARKDOWN] HIGH extension overhead detected (${extensionOverhead.toFixed(2)}ms)`);
					}
				}

				parserUsed = fallbackUsed ? 'marked (fallback from unified)' : 'marked (with extensions)';
				parserMetrics = {
					totalTime: extTime,
					tokenCount: tokens.length,
					bareTime,
					extensionOverhead: bareTime !== undefined ? extTime - bareTime : undefined
				};
			} catch (error) {
				console.error(`[MARKDOWN] ✗ Marked+extensions failed:`, error?.message);
				console.error(`[MARKDOWN] Stack:`, error?.stack);
				parserUsed = 'FAILED';
			}
		}

		// Final summary
		const endTime = performance.now();
		const totalTime = endTime - startTime;

		console.log(`\n`);
		console.log(`╔═══════════════════════════════════════════════════════════════════════════╗`);
		console.log(`║                        PROCESSING COMPLETE                                 ║`);
		console.log(`╚═══════════════════════════════════════════════════════════════════════════╝`);
		console.log(`[MARKDOWN] Parser used: ${parserUsed}`);
		console.log(`[MARKDOWN] Fallback used: ${fallbackUsed ? 'YES' : 'NO'}`);
		console.log(`[MARKDOWN] Total tokens: ${tokens.length}`);

		console.log(`\n[MARKDOWN] ═══ PERFORMANCE BREAKDOWN ═══`);
		console.log(`[MARKDOWN] Pre-process:     ${performanceMarks.preprocess?.toFixed(2) || '0.00'}ms`);
		console.log(`[MARKDOWN] Token replace:   ${performanceMarks.replaceTokens?.toFixed(2) || '0.00'}ms`);

		if (parserUsed.includes('unified')) {
			console.log(`[MARKDOWN] Parse (unified): ${parserMetrics.parseTime?.toFixed(2) || '0.00'}ms`);
			console.log(`[MARKDOWN] Convert:         ${parserMetrics.convertTime?.toFixed(2) || '0.00'}ms`);
			console.log(`[MARKDOWN] Unified wall time: ${parserMetrics.totalWallTime?.toFixed(2) || '0.00'}ms`);
		} else if (parserUsed.includes('marked')) {
			if (bareTime !== undefined) {
				console.log(`[MARKDOWN] Marked (bare):   ${bareTime?.toFixed(2)}ms`);
				console.log(
					`[MARKDOWN] Extensions:      ${parserMetrics.extensionOverhead?.toFixed(2) || '0.00'}ms`
				);
			}
			console.log(`[MARKDOWN] Marked (total):  ${parserMetrics.totalTime?.toFixed(2) || '0.00'}ms`);
		}

		console.log(`[MARKDOWN] ────────────────────────────────────────`);
		console.log(`[MARKDOWN] TOTAL TIME:      ${totalTime.toFixed(2)}ms`);
		console.log(
			`[MARKDOWN] Throughput:      ${(
				contentWithReplacedTokens.length / Math.max(totalTime, 0.0001)
			).toFixed(0)} chars/ms`
		);

		// Performance assessment
		console.log(`\n[MARKDOWN] ═══ PERFORMANCE ASSESSMENT ═══`);
		if (totalTime < 50) {
			console.log(`[MARKDOWN] EXCELLENT (${totalTime.toFixed(0)}ms < 50ms)`);
		} else if (totalTime < 100) {
			console.log(`[MARKDOWN] GOOD (${totalTime.toFixed(0)}ms < 100ms)`);
		} else if (totalTime < 500) {
			console.log(`[MARKDOWN] ACCEPTABLE (${totalTime.toFixed(0)}ms < 500ms)`);
		} else if (totalTime < 1000) {
			console.log(`[MARKDOWN] SLOW (${totalTime.toFixed(0)}ms < 1000ms)`);
		} else if (totalTime < 5000) {
			console.log(`[MARKDOWN] VERY SLOW (${totalTime.toFixed(0)}ms < 5000ms)`);
		} else {
			console.log(
				`[MARKDOWN] CRITICAL (${totalTime.toFixed(
					0
				)}ms >= 5000ms) - Main-thread freeze likely in original path`
			);
		}

		console.log(`\n[MARKDOWN] Completed at: ${new Date().toISOString()}`);
		console.log(`╚═══════════════════════════════════════════════════════════════════════════╝\n\n`);
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

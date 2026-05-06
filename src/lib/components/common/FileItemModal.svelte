<script lang="ts">
	import type { WorkBook } from 'xlsx';
	import DOMPurify from 'dompurify';

	import { getContext, onMount, tick, createEventDispatcher } from 'svelte';

	import { formatFileSize, getLineCount, copyToClipboard } from '$lib/utils';
	import { WEBUI_API_BASE_URL } from '$lib/constants';
	import { settings } from '$lib/stores';
	import { getKnowledgeById } from '$lib/apis/knowledge';
	import { getFileById, getFileContentById, updateFileDataContentById, updateFileById } from '$lib/apis/files';
	import { toast } from 'svelte-sonner';

	import { languages } from '@codemirror/language-data';
	import Selector from './Selector.svelte';

	import CodeBlock from '$lib/components/chat/Messages/CodeBlock.svelte';
	import Markdown from '$lib/components/chat/Messages/Markdown.svelte';
	import CodeEditor from '$lib/components/common/CodeEditor.svelte';
	import Clipboard from '$lib/components/icons/Clipboard.svelte';
	import Check from '$lib/components/icons/Check.svelte';
	import EditPencil from '$lib/components/icons/EditPencil.svelte';
	import FloppyDisk from '$lib/components/icons/FloppyDisk.svelte';

	const i18n = getContext('i18n');
	const dispatch = createEventDispatcher();

	const CONTENT_PREVIEW_LIMIT = 10000;
	let expandedContent = false;

	import Modal from './Modal.svelte';
	import XMark from '../icons/XMark.svelte';
	import Switch from './Switch.svelte';
	import Tooltip from './Tooltip.svelte';
	import dayjs from 'dayjs';
	import Spinner from './Spinner.svelte';
	import PDFViewer from './PDFViewer.svelte';
	import PanzoomContainer from './PanzoomContainer.svelte';
	import Reset from '../icons/Reset.svelte';

	export let item;
	export let show = false;
	export let edit = false;

	let enableFullContent = false;
	let loading = false;

	let isPDF = false;
	let isAudio = false;
	let isImage = false;
	let isExcel = false;
	let isDocx = false;
	let isPptx = false;

	let selectedTab = '';
	let excelWorkbook: WorkBook | null = null;
	let excelSheetNames: string[] = [];
	let selectedSheet = '';
	let excelHtml = '';
	let excelError = '';
	let rowCount = 0;

	// DOCX state
	let docxHtml = '';
	let docxError = '';

	// PPTX state
	let pptxSlides: string[] = [];
	let pptxCurrentSlide = 0;
	let pptxError = '';

	let panzoomRef: PanzoomContainer;
	const resetImageView = () => {
		panzoomRef?.reset();
	};

	$: isPDF =
		item?.meta?.content_type === 'application/pdf' ||
		(item?.name && item?.name.toLowerCase().endsWith('.pdf'));

	$: isMarkdown =
		item?.meta?.content_type === 'text/markdown' ||
		(item?.name && item?.name.toLowerCase().endsWith('.md'));

	$: isCode =
		item?.name &&
		(item.name.toLowerCase().endsWith('.py') ||
			item.name.toLowerCase().endsWith('.js') ||
			item.name.toLowerCase().endsWith('.ts') ||
			item.name.toLowerCase().endsWith('.java') ||
			item.name.toLowerCase().endsWith('.html') ||
			item.name.toLowerCase().endsWith('.css') ||
			item.name.toLowerCase().endsWith('.json') ||
			item.name.toLowerCase().endsWith('.cpp') ||
			item.name.toLowerCase().endsWith('.c') ||
			item.name.toLowerCase().endsWith('.h') ||
			item.name.toLowerCase().endsWith('.sh') ||
			item.name.toLowerCase().endsWith('.bash') ||
			item.name.toLowerCase().endsWith('.yaml') ||
			item.name.toLowerCase().endsWith('.yml') ||
			item.name.toLowerCase().endsWith('.xml') ||
			item.name.toLowerCase().endsWith('.sql') ||
			item.name.toLowerCase().endsWith('.go') ||
			item.name.toLowerCase().endsWith('.rs') ||
			item.name.toLowerCase().endsWith('.php') ||
			item.name.toLowerCase().endsWith('.rb'));

	$: isAudio =
		(item?.meta?.content_type ?? '').startsWith('audio/') ||
		(item?.name && item?.name.toLowerCase().endsWith('.mp3')) ||
		(item?.name && item?.name.toLowerCase().endsWith('.wav')) ||
		(item?.name && item?.name.toLowerCase().endsWith('.ogg')) ||
		(item?.name && item?.name.toLowerCase().endsWith('.m4a')) ||
		(item?.name && item?.name.toLowerCase().endsWith('.webm'));

	$: isImage =
		(item?.meta?.content_type ?? '').startsWith('image/') ||
		(item?.name &&
			(item.name.toLowerCase().endsWith('.png') ||
				item.name.toLowerCase().endsWith('.jpg') ||
				item.name.toLowerCase().endsWith('.jpeg') ||
				item.name.toLowerCase().endsWith('.gif') ||
				item.name.toLowerCase().endsWith('.webp') ||
				item.name.toLowerCase().endsWith('.svg') ||
				item.name.toLowerCase().endsWith('.bmp') ||
				item.name.toLowerCase().endsWith('.ico')));

	$: isExcel =
		item?.meta?.content_type === 'application/vnd.ms-excel' ||
		item?.meta?.content_type ===
			'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
		item?.meta?.content_type === 'text/csv' ||
		item?.meta?.content_type === 'application/csv' ||
		(item?.name &&
			(item.name.toLowerCase().endsWith('.xls') ||
				item.name.toLowerCase().endsWith('.xlsx') ||
				item.name.toLowerCase().endsWith('.csv')));

	$: isDocx =
		item?.meta?.content_type ===
			'application/vnd.openxmlformats-officedocument.wordprocessingml.document' ||
		(item?.name && item.name.toLowerCase().endsWith('.docx'));

	$: isPptx =
		item?.meta?.content_type ===
			'application/vnd.openxmlformats-officedocument.presentationml.presentation' ||
		(item?.name && item.name.toLowerCase().endsWith('.pptx'));

	const loadExcelContent = async () => {
		try {
			excelError = '';
			const [arrayBuffer, { read }] = await Promise.all([
				getFileContentById(item.id),
				import('xlsx')
			]);
			excelWorkbook = read(arrayBuffer, { type: 'array' });
			excelSheetNames = excelWorkbook.SheetNames;

			if (excelSheetNames.length > 0) {
				selectedSheet = excelSheetNames[0];
				await renderExcelSheet();
			}
		} catch (error) {
			console.error('Error loading Excel/CSV file:', error);
			excelError = $i18n.t('Failed to load Excel/CSV file. Please try downloading it instead.');
		}
	};

	const renderExcelSheet = async () => {
		if (!excelWorkbook || !selectedSheet) return;
		const { excelToTable } = await import('$lib/utils/excelToTable');
		const worksheet = excelWorkbook.Sheets[selectedSheet];
		const result = await excelToTable(worksheet);
		excelHtml = result.html;
		rowCount = result.rowCount;
	};

	$: if (selectedSheet && excelWorkbook) {
		renderExcelSheet();
	}

	const loadDocxContent = async () => {
		try {
			docxError = '';
			const [arrayBuffer, mammoth] = await Promise.all([
				getFileContentById(item.id),
				import('mammoth')
			]);
			const result = await mammoth.convertToHtml({ arrayBuffer });
			docxHtml = DOMPurify.sanitize(result.value);
		} catch (error) {
			console.error('Error loading DOCX file:', error);
			docxError = $i18n.t('Failed to load DOCX file. Please try downloading it instead.');
		}
	};

	const loadPptxContent = async () => {
		try {
			pptxError = '';
			const [arrayBuffer, { pptxToImages }] = await Promise.all([
				getFileContentById(item.id),
				import('$lib/utils/pptxToHtml')
			]);
			const result = await pptxToImages(arrayBuffer);
			pptxSlides = result.images;
			pptxCurrentSlide = 0;
		} catch (error) {
			console.error('Error loading PPTX file:', error);
			pptxError = $i18n.t('Failed to load PPTX file. Please try downloading it instead.');
		}
	};

	const loadContent = async () => {
		selectedTab = '';
		expandedContent = false;
		if (item?.type === 'collection') {
			loading = true;

			const knowledge = await getKnowledgeById(localStorage.token, item.id).catch((e) => {
				console.error('Error fetching knowledge base:', e);
				return null;
			});

			if (knowledge) {
				item.files = knowledge.files || [];
			}
			loading = false;
		} else if (item?.type === 'file') {
			loading = true;

			const file = await getFileById(localStorage.token, item.id).catch((e) => {
				console.error('Error fetching file:', e);
				return null;
			});

			if (file) {
				item.file = file || {};
			}

			// Load Excel content if it's an Excel file
			if (isExcel) {
				await loadExcelContent();
			}
			if (isDocx) {
				await loadDocxContent();
			}
			if (isPptx) {
				await loadPptxContent();
			}

			loading = false;
		}

		await tick();
	};

	$: if (show) {
		loadContent();
	}

	onMount(() => {
		console.log(item);
		if (item?.context === 'full') {
			enableFullContent = true;
		}
	});

	// --- Start Synthesized Copy/Edit Logic ---
	type ModalMode = 'view' | 'edit';
	let mode: ModalMode = 'view';
	let isSaving = false;
	let copied = false;
	let copyTimeout: ReturnType<typeof setTimeout> | null = null;
	
	let draftContent = '';
	let originalContent = '';

	let isRenaming = false;
	let fileNameDraft = '';

	$: isText =
		isMarkdown ||
		isCode ||
		(!isPDF &&
			!isImage &&
			!isAudio &&
			!isExcel &&
			!isDocx &&
			!isPptx &&
			(item?.file?.data?.content !== undefined || item?.content !== undefined));
	$: canEdit = isText; // Always allow edit if it's text
	$: isDirty = mode === 'edit' && draftContent !== originalContent;

	const languageOptions = languages
		.map((l) => ({
			value: l.alias[0],
			label: l.name
		}))
		.sort((a, b) => a.label.localeCompare(b.label));

	function detectLang(name: string = ''): string {
		const ext = name.split('.').pop()?.toLowerCase() ?? '';
		if (ext) {
			const language = languages.find((l) => l.extensions.includes(ext));
			if (language) {
				return language.alias[0];
			}
		}
		return 'text';
	}

	let editorLang = 'text';
	$: if (item) {
		editorLang = detectLang(item?.file?.filename ?? item?.file?.name ?? '');
	}

	$: if (show && mode === 'view' && item) {
		const currentContent = String(item?.file?.data?.content ?? item?.content ?? '');
		if (currentContent !== originalContent) {
			originalContent = currentContent;
			draftContent = currentContent;
		}
	}

	const handleCopy = async () => {
		const content = item?.file?.data?.content ?? item?.content ?? '';
		if (!content) return;

		const ok = await copyToClipboard(content);
		if (!ok) {
			toast.error($i18n.t('Failed to copy to clipboard'));
			return;
		}

		copied = true;
		if (copyTimeout) clearTimeout(copyTimeout);
		copyTimeout = setTimeout(() => (copied = false), 1500);
	};

	const enterEdit = async () => {
		if (!canEdit || isSaving) return;
		originalContent = item?.file?.data?.content ?? item?.content ?? '';
		draftContent = originalContent;
		mode = 'edit';
		if (copyTimeout) {
			clearTimeout(copyTimeout);
			copied = false;
		}
		await tick();
	};

	const handleCancel = () => {
		if (isSaving) return;
		if (isDirty && !window.confirm($i18n.t('Discard unsaved changes?'))) return;
		draftContent = originalContent;
		mode = 'view';
	};

	const requestClose = () => {
		if (isSaving) return;
		if (mode === 'edit' && isDirty && !window.confirm($i18n.t('Discard unsaved changes?'))) return;
		draftContent = originalContent;
		mode = 'view';
		show = false;
	};

	const handleRename = async () => {
		if (!fileNameDraft || fileNameDraft === (item?.file?.filename ?? item?.file?.name)) {
			isRenaming = false;
			return;
		}

		try {
			const res = await updateFileById(localStorage.token, item.id, {
				filename: fileNameDraft
			});

			if (res) {
				// MERGE: Preserve data.content by merging 'res' into existing file object
				item.file = { ...item.file, ...res };
				item.name = res.filename;
				item = { ...item };

				fileNameDraft = res.filename;
				toast.success($i18n.t('File renamed successfully'));
				dispatch('save', item);
			}
		} catch (e) {
			console.error(e);
			toast.error($i18n.t('Failed to rename file'));
		} finally {
			isRenaming = false;
		}
	};

	const handleSave = async () => {
		if (isSaving || !isDirty || !canEdit) return;

		const token = localStorage.token;
		isSaving = true;
		try {
			const res = await updateFileDataContentById(token, item.id, draftContent);
			if (!res) throw new Error('No response');

			const savedContent =
				res?.file?.data?.content ?? res?.data?.content ?? res?.content ?? draftContent;
			const previousFile = item?.file ?? {};
			const previousData = previousFile?.data ?? {};

			item = {
				...item,
				file: {
					...previousFile,
					data: {
						...previousData,
						content: savedContent
					}
				}
			};

			originalContent = savedContent;
			draftContent = savedContent;
			mode = 'view';
			toast.success($i18n.t('File saved'));
			dispatch('save', item);
		} catch (e) {
			console.error(e);
			toast.error($i18n.t('Failed to save file'));
		} finally {
			isSaving = false;
		}
	};
	// --- End Synthesized Copy/Edit Logic ---
</script>

<Modal bind:show onClose={requestClose} size="lg">
	<div class="font-primary px-4.5 py-3.5 w-full flex flex-col justify-center dark:text-gray-400">
		<div class=" pb-2">
			<div class="flex items-start justify-between">
				<div class="group">
					<div class="flex items-center gap-1.5 font-medium text-lg dark:text-gray-100">
						{#if isRenaming}
							<input
								class="w-full bg-transparent outline-hidden border-b border-gray-500 pb-0.5"
								bind:value={fileNameDraft}
								on:keydown={(e) => {
									if (e.key === 'Enter') handleRename();
									if (e.key === 'Escape') isRenaming = false;
								}}
								autofocus
							/>
							<button class="p-1 hover:text-gray-900 dark:hover:text-white transition" on:click={handleRename}>
								<FloppyDisk className="size-4" />
							</button>
							<button class="p-1 hover:text-gray-900 dark:hover:text-white transition" on:click={() => (isRenaming = false)}>
								<XMark className="size-4" />
							</button>
						{:else}
							<a
								href="#"
								class="hover:underline line-clamp-1"
								on:click|preventDefault={() => {
									if (!isPDF && item.url) {
										window.open(
											item.type === 'file'
												? item?.url?.startsWith('http')
													? item.url
													: `${WEBUI_API_BASE_URL}/files/${item.url}/content`
												: item.url,
											'_blank'
										);
									}
								}}
							>
								{item?.file?.filename ?? item?.file?.name ?? item?.name ?? $i18n.t('File')}
							</a>
							<button
								class="p-1 text-gray-400 hover:text-gray-900 dark:hover:text-white transition opacity-0 group-hover:opacity-100 focus:opacity-100"
								on:click={() => {
									fileNameDraft = item?.file?.filename ?? item?.file?.name ?? item?.name;
									isRenaming = true;
								}}
							>
								<EditPencil className="size-3.5" />
							</button>
						{/if}
					</div>
				</div>

				<div class="flex items-center gap-1 shrink-0">
					{#if canEdit}
						<div class="mr-1 mt-0.5">
							<Selector
											bind:value={editorLang}
											items={languageOptions}
											align="end"
											placeholder={$i18n.t('Plain Text')}
											searchPlaceholder={$i18n.t('Search language...')}
										/>						</div>
					{/if}

					{#if mode === 'view' && isText}
						<Tooltip content={copied ? $i18n.t('Copied') : $i18n.t('Copy')}>
							<button
								class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-850 transition self-center"
								on:click={handleCopy}
							>
								{#if copied}
									<Check className="size-4 text-green-500" strokeWidth="2.5" />
								{:else}
									<Clipboard className="size-4" strokeWidth="2" />
								{/if}
							</button>
						</Tooltip>
						<Tooltip content={$i18n.t('Edit')}>
							<button
								class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-850 transition self-center"
								on:click={enterEdit}
							>
								<EditPencil className="size-4" strokeWidth="2" />
							</button>
						</Tooltip>
					{:else if mode === 'edit'}
						<Tooltip content={$i18n.t('Save')}>
							<button
								class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-850 transition self-center disabled:opacity-40 disabled:cursor-not-allowed"
								on:click={handleSave}
								disabled={isSaving || !isDirty}
							>
								{#if isSaving}
									<Spinner className="size-4" />
								{:else}
									<FloppyDisk className="size-4" strokeWidth="2" />
								{/if}
							</button>
						</Tooltip>
						<Tooltip content={$i18n.t('Cancel')}>
							<button
								class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-850 transition self-center disabled:opacity-40 disabled:cursor-not-allowed"
								on:click={handleCancel}
								disabled={isSaving}
							>
								<XMark className="size-4" strokeWidth="2" />
							</button>
						</Tooltip>
					{/if}

					<div class="mx-1 h-5 w-px bg-gray-200 dark:bg-gray-800" aria-hidden="true" />

					<Tooltip content={$i18n.t('Close')}>
						<button
							class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-850 transition self-center"
							on:click={requestClose}
						>
							<XMark className="size-4" strokeWidth="2" />
						</button>
					</Tooltip>
				</div>
			</div>

			<div>
				<div class="flex flex-col items-center md:flex-row gap-1 justify-between w-full">
					<div class=" flex flex-wrap text-xs gap-1 text-gray-500">
						{#if item?.type === 'collection'}
							{#if item?.type}
								<div class="capitalize shrink-0">{item.type}</div>
								•
							{/if}

							{#if item?.description}
								<div class="line-clamp-1">{item.description}</div>
								•
							{/if}

							{#if item?.created_at}
								<div class="capitalize shrink-0">
									{dayjs(item.created_at * 1000).format('LL')}
								</div>
							{/if}
						{/if}

						{#if item.size}
							<div class="capitalize shrink-0">{formatFileSize(item.size)}</div>
							•
						{/if}

						{#if item?.file?.data?.content}
							<div class="capitalize shrink-0">
								{#if isExcel && rowCount > 0 && selectedTab === 'preview'}
									{$i18n.t('{{COUNT}} Rows', {
										COUNT: rowCount
									})}
								{:else}
									{$i18n.t('{{COUNT}} extracted lines', {
										COUNT: getLineCount(item?.file?.data?.content ?? '')
									})}
								{/if}
							</div>

							<div class="flex items-center gap-1 shrink-0">
								• {$i18n.t('Formatting may be inconsistent from source.')}
							</div>
						{/if}

						{#if item?.knowledge}
							<div class="capitalize shrink-0">
								{$i18n.t('Knowledge Base')}
							</div>
						{/if}
					</div>

					{#if edit}
						<div class=" self-end">
							<Tooltip
								content={enableFullContent
									? $i18n.t(
											'Inject the entire content as context for comprehensive processing, this is recommended for complex queries.'
										)
									: $i18n.t(
											'Default to segmented retrieval for focused and relevant content extraction, this is recommended for most cases.'
										)}
							>
								<div class="flex items-center gap-1.5 text-xs">
									{#if enableFullContent}
										{$i18n.t('Using Entire Document')}
									{:else}
										{$i18n.t('Using Focused Retrieval')}
									{/if}
									<Switch
										bind:state={enableFullContent}
										on:change={(e) => {
											item.context = e.detail ? 'full' : undefined;
										}}
									/>
								</div>
							</Tooltip>
						</div>
					{/if}
				</div>
			</div>
		</div>

		<div class="max-h-[75vh] overflow-auto">
			{#if !loading}
				{#if item?.type === 'collection'}
					<div>
						{#each item?.files as file}
							<div class="flex items-center gap-2 mb-2">
								<div class="flex-shrink-0 text-xs">
									{file?.meta?.name}
								</div>
							</div>
						{/each}
					</div>
				{/if}

				{#if mode === 'view' && (isAudio || isPDF || isExcel || isCode || isMarkdown || isDocx || isPptx || isText)}
					<div
						class="flex mb-2.5 scrollbar-none overflow-x-auto w-full border-b border-gray-50 dark:border-gray-850/30 text-center text-sm font-medium bg-transparent dark:text-gray-200"
					>
						<button
							class="min-w-fit py-1.5 px-4 border-b {selectedTab === ''
								? ' '
								: ' border-transparent text-gray-300 dark:text-gray-600 hover:text-gray-700 dark:hover:text-white'} transition"
							type="button"
							on:click={() => {
								selectedTab = '';
							}}>{$i18n.t('Content')}</button
						>

						<button
							class="min-w-fit py-1.5 px-4 border-b {selectedTab === 'preview'
								? ' '
								: ' border-transparent text-gray-300 dark:text-gray-600 hover:text-gray-700 dark:hover:text-white'} transition"
							type="button"
							on:click={() => {
								selectedTab = 'preview';
							}}>{$i18n.t('Preview')}</button
						>
					</div>
				{/if}

				{#if isImage}
					<div class="relative w-full max-h-[70vh] overflow-hidden">
						<div class="absolute top-2 right-2 z-10">
							<Tooltip content={$i18n.t('Reset view')}>
								<button
									class="p-1.5 rounded-lg bg-white/80 dark:bg-gray-850/80 backdrop-blur-sm shadow-sm hover:bg-gray-100 dark:hover:bg-gray-800 transition text-gray-500 dark:text-gray-400"
									on:click={resetImageView}
								>
									<Reset className="size-4" />
								</button>
							</Tooltip>
						</div>
						<PanzoomContainer bind:this={panzoomRef}>
							<img
								src={`${WEBUI_API_BASE_URL}/files/${item.id}/content`}
								alt={item?.name ?? 'Image'}
								class="w-full object-contain rounded-lg"
								loading="lazy"
								draggable="false"
							/>
						</PanzoomContainer>
					</div>
				{:else if mode === 'edit'}
					<div class="file-modal-editor-shell relative overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-950">
						<CodeEditor
							id={`file-editor-${item.id}`}
							value={draftContent}
							lang={editorLang}
							onChange={(val) => {
								draftContent = val;
							}}
							onSave={handleSave}
						/>
						{#if isSaving}
							<div class="absolute inset-0 z-10 flex items-start justify-end bg-white/50 p-3 backdrop-blur-[1px] dark:bg-black/30" aria-hidden="true">
								<div class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white px-3 py-1.5 text-xs font-medium text-gray-700 shadow-sm dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200">
									<span class="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
									{$i18n.t('Saving...')}
								</div>
							</div>
						{/if}
					</div>
				{:else if selectedTab === ''}
					{#if item?.file?.data}
						{@const rawContent = (item?.file?.data?.content ?? '').trim() || 'No content'}
						{@const isTruncated =
							($settings?.renderMarkdownInPreviews ?? true) &&
							rawContent.length > CONTENT_PREVIEW_LIMIT &&
							!expandedContent}
						{#if $settings?.renderMarkdownInPreviews ?? true}
							<div
								class="max-h-96 overflow-scroll scrollbar-hidden text-sm prose dark:prose-invert max-w-full"
							>
								<Markdown
									content={isTruncated ? rawContent.slice(0, CONTENT_PREVIEW_LIMIT) : rawContent}
									id="file-preview"
								/>
							</div>
							{#if isTruncated}
								<button
									class="mt-1 text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition"
									on:click={() => {
										expandedContent = true;
									}}
								>
									{$i18n.t('Show all ({{COUNT}} characters)', {
										COUNT: rawContent.length.toLocaleString()
									})}
								</button>
							{/if}
						{:else}
							<div class="max-h-96 overflow-scroll scrollbar-hidden text-xs whitespace-pre-wrap">
								{rawContent}
							</div>
						{/if}
					{:else if item?.content}
						{@const rawContent = (item?.content ?? '').trim() || 'No content'}
						{@const isTruncated =
							($settings?.renderMarkdownInPreviews ?? true) &&
							rawContent.length > CONTENT_PREVIEW_LIMIT &&
							!expandedContent}
						{#if $settings?.renderMarkdownInPreviews ?? true}
							<div
								class="max-h-96 overflow-scroll scrollbar-hidden text-sm prose dark:prose-invert max-w-full"
							>
								<Markdown
									content={isTruncated ? rawContent.slice(0, CONTENT_PREVIEW_LIMIT) : rawContent}
									id="file-preview-content"
								/>
							</div>
							{#if isTruncated}
								<button
									class="mt-1 text-xs text-gray-500 hover:text-gray-700 dark:hover:text-gray-300 transition"
									on:click={() => {
										expandedContent = true;
									}}
								>
									{$i18n.t('Show all ({{COUNT}} characters)', {
										COUNT: rawContent.length.toLocaleString()
									})}
								</button>
							{/if}
						{:else}
							<div class="max-h-96 overflow-scroll scrollbar-hidden text-xs whitespace-pre-wrap">
								{rawContent}
							</div>
						{/if}
					{/if}
				{:else if selectedTab === 'preview'}
					{#if isAudio}
						<audio
							src={`${WEBUI_API_BASE_URL}/files/${item.id}/content`}
							class="w-full border-0 rounded-lg mb-2"
							controls
							playsinline
						/>
					{:else if isPDF}
						<PDFViewer
							url={`${WEBUI_API_BASE_URL}/files/${item.id}/content`}
							className="w-full h-[70vh] border-0 rounded-lg"
						/>
					{:else if isExcel}
						{#if excelError}
							<div class="text-red-500 text-sm p-4">
								{excelError}
							</div>
						{:else}
							{#if excelSheetNames.length > 1}
								<div
									class="flex mb-2.5 scrollbar-none overflow-x-auto w-full border-b border-gray-50 dark:border-gray-850/30 text-center text-sm font-medium bg-transparent dark:text-gray-200"
								>
									{#each excelSheetNames as sheetName}
										<button
											class="min-w-fit py-1.5 px-4 border-b {selectedSheet === sheetName
												? ' '
												: ' border-transparent text-gray-300 dark:text-gray-600 hover:text-gray-700 dark:hover:text-white'} transition"
											type="button"
											on:click={() => {
												selectedSheet = sheetName;
											}}>{sheetName}</button
										>
									{/each}
								</div>
							{/if}

							{#if excelHtml}
								<div class="office-preview overflow-auto max-h-[60vh]">
									{@html excelHtml}
								</div>
							{:else}
								<div class="text-gray-500 text-sm p-4">No content available</div>
							{/if}
						{/if}
					{:else if isCode}
						<div class="max-h-[60vh] overflow-scroll scrollbar-hidden text-sm relative">
							<CodeBlock
								code={item.file.data.content}
								lang={item.name.split('.').pop()}
								token={null}
								edit={false}
								run={false}
								save={false}
							/>
						</div>
					{:else if isMarkdown}
						<div
							class="max-h-[60vh] overflow-scroll scrollbar-hidden text-sm prose dark:prose-invert max-w-full"
						>
							<Markdown content={item.file.data.content} id="markdown-viewer" />
						</div>
					{:else if isDocx}
						{#if docxError}
							<div class="text-red-500 text-sm p-4">{docxError}</div>
						{:else if docxHtml}
							<div
								class="office-preview max-h-[60vh] overflow-auto p-4 prose dark:prose-invert max-w-full text-sm"
							>
								{@html docxHtml}
							</div>
						{:else}
							<div class="text-gray-500 text-sm p-4">No content available</div>
						{/if}
					{:else if isPptx}
						{#if pptxError}
							<div class="text-red-500 text-sm p-4">{pptxError}</div>
						{:else if pptxSlides.length > 0}
							<div class="max-h-[60vh] overflow-auto">
								<div class="flex justify-center p-4">
									<img
										src={pptxSlides[pptxCurrentSlide]}
										alt="Slide {pptxCurrentSlide + 1}"
										class="max-w-full max-h-[50vh] object-contain rounded-md shadow-lg"
										draggable="false"
									/>
								</div>
								{#if pptxSlides.length > 1}
									<div class="flex items-center justify-center gap-3 pb-3 text-sm text-gray-500">
										<button
											class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-30"
											disabled={pptxCurrentSlide === 0}
											on:click={() => (pptxCurrentSlide = Math.max(0, pptxCurrentSlide - 1))}
										>
											<svg
												xmlns="http://www.w3.org/2000/svg"
												viewBox="0 0 20 20"
												fill="currentColor"
												class="size-5"
											>
												<path
													fill-rule="evenodd"
													d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z"
													clip-rule="evenodd"
												/>
											</svg>
										</button>
										<span>{pptxCurrentSlide + 1} / {pptxSlides.length}</span>
										<button
											class="p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 disabled:opacity-30"
											disabled={pptxCurrentSlide === pptxSlides.length - 1}
											on:click={() =>
												(pptxCurrentSlide = Math.min(pptxSlides.length - 1, pptxCurrentSlide + 1))}
										>
											<svg
												xmlns="http://www.w3.org/2000/svg"
												viewBox="0 0 20 20"
												fill="currentColor"
												class="size-5"
											>
												<path
													fill-rule="evenodd"
													d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z"
													clip-rule="evenodd"
												/>
											</svg>
										</button>
									</div>
								{/if}
							</div>
						{:else}
							<div class="text-gray-500 text-sm p-4">No content available</div>
						{/if}
					{:else if isText}
						<div class="max-h-96 overflow-scroll scrollbar-hidden text-xs whitespace-pre-wrap">
							{(item?.file?.data?.content ?? item?.content ?? '').trim() || 'No content'}
						</div>
					{:else}
						<div class="text-gray-500 text-sm p-4">{$i18n.t('No content available')}</div>
					{/if}
				{/if}
			{:else}
				<div class="flex items-center justify-center py-6">
					<Spinner className="size-5" />
				</div>
			{/if}
		</div>
	</div>
</Modal>

<style>
	:global(.excel-table-container table) {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.875rem;
		line-height: 1.25rem;
	}

	:global(.excel-table-container table td),
	:global(.excel-table-container table th) {
		border-width: 1px;
		border-style: solid;
		border-color: var(--color-gray-300, #cdcdcd);
		padding: 0.5rem 0.75rem;
		text-align: left;
	}

	:global(.dark .excel-table-container table td),
	:global(.dark .excel-table-container table th) {
		border-color: var(--color-gray-600, #676767);
	}

	:global(.excel-table-container table th) {
		background-color: var(--color-gray-100, #ececec);
		font-weight: 600;
	}

	:global(.dark .excel-table-container table th) {
		background-color: var(--color-gray-800, #333);
		color: var(--color-gray-100, #ececec);
	}

	:global(.excel-table-container table tr:nth-child(even)) {
		background-color: var(--color-gray-50, #f9f9f9);
	}

	:global(.dark .excel-table-container table tr:nth-child(even)) {
		background-color: rgba(38, 38, 38, 0.5);
	}

	:global(.excel-table-container table tr:hover) {
		background-color: var(--color-gray-100, #ececec);
	}

	:global(.dark .excel-table-container table tr:hover) {
		background-color: rgba(51, 51, 51, 0.5);
	}

	.file-modal-editor-shell :global(.cm-editor) {
		height: min(62vh, 720px);
		min-height: 420px;
	}

	.file-modal-editor-shell :global(.cm-scroller) {
		overflow: auto;
	}

	@media (max-width: 640px) {
		.file-modal-editor-shell :global(.cm-editor) {
			height: 58vh;
			min-height: 320px;
		}
	}
</style>

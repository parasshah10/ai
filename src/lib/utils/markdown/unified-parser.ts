import { unified } from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';

type ParseMetrics = {
  totalTime: number;
  parseTime: number;
  convertTime: number;
  tokenCount: number;
  nodeCount: number;
  contentStats: {
    codeBlocks: number;
    tables: number;
    lists: number;
    headings: number;
    links: number;
    images: number;
    inlineMath: number;
    mathBlocks: number;
  };
};

type ParseResult =
  | {
      success: true;
      tokens: any[];
      metrics: ParseMetrics;
    }
  | {
    success: false;
    error: any;
    metrics: ParseMetrics;
  };

/**
 * Unified-based parser (same parser family LibreChat uses via react-markdown)
 * Parses markdown to MDAST (remark) and converts to the token shape expected by our Svelte renderers.
 * Final version: no console logging. Includes math (inlineMath, math) mapping to inlineKatex/blockKatex.
 */
// Comprehensive heuristic to detect a wide range of markdown features.
const MARKDOWN_QUICK_SCAN_REGEX =
	/^(?:#|>|\*|-|\d+\.|\s*\|)\s|```|---|\[.+\]\(.+\)|!\[.*\]\(.*\)|\[.+\]:.*|\$.+\$|<(?:div|table|details|pre|code)|(?:\*\*|__|_|~~|`|\[\^.*\])/m;

// Regex for hard-block segmentation
const FENCED_CODE_REGEX = /^(\s*)(`{3,}|~{3,})([^\n]*)\n([\s\S]+?)\n\s*\2\s*$/gm;
const BLOCK_MATH_REGEX = /^\$\$\n([\s\S]+?)\n\$\$\s*$/gm;
const BLOCK_HTML_REGEX = /^<(details|div|table|pre|code)[\s>][\s\S]*?<\/\1>\s*$/gm;
// Extract horizontal rules to prevent them from creating Setext headings
const HORIZONTAL_RULE_REGEX = /^(\s*)([-*_])\2{2,}\s*$/gm;

export function parseMarkdownToTokens(
	content: string,
	messageId: string,
	useHybrid = false
): ParseResult {
	const perfStart = performance.now();

	const metrics: ParseMetrics = {
		totalTime: 0,
		parseTime: 0,
		convertTime: 0,
		tokenCount: 0,
		nodeCount: 0,
		contentStats: {
			codeBlocks: 0,
			tables: 0,
			lists: 0,
			headings: 0,
			links: 0,
			images: 0,
			inlineMath: 0,
			mathBlocks: 0
		}
	};

	try {
		const parseStart = performance.now();
		const tree: any = unified().use(remarkParse).use(remarkGfm).use(remarkMath).parse(content);
		const parseEnd = performance.now();
		metrics.parseTime = parseEnd - parseStart;
		metrics.nodeCount = countNodes(tree);

		metrics.contentStats = analyzeContent(tree);

		const convertStart = performance.now();
		const tokens = convertMdastToMarkedTokens(tree);
		const convertEnd = performance.now();
		metrics.convertTime = convertEnd - convertStart;
		metrics.tokenCount = tokens.length;

		metrics.totalTime = performance.now() - perfStart;

		return { success: true, tokens, metrics };
	} catch (error: any) {
		metrics.totalTime = performance.now() - perfStart;
		return { success: false, error, metrics };
	}
}

/**
 * Convert remark MDAST tree into a minimal "marked-like" token array compatible with existing render pipeline.
 * Includes mapping for math:
 *  - inlineMath -> { type: 'inlineKatex', text, displayMode: false }
 *  - math       -> { type: 'blockKatex',  text, displayMode: true  }
 */
function convertMdastToMarkedTokens(tree: any): any[] {
  const tokens: any[] = [];
  const children: any[] = Array.isArray(tree?.children) ? tree.children : [];

  for (const node of children) {
    const token = convertNode(node);
    if (token) tokens.push(token);
  }
  return tokens;
}

function convertNode(node: any): any {
  switch (node?.type) {
    case 'heading':
      return {
        type: 'heading',
        depth: node.depth,
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'paragraph':
      return {
        type: 'paragraph',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'code':
      return {
        type: 'code',
        lang: node.lang || '',
        text: node.value || '',
        raw: `\`\`\`${node.lang || ''}\n${node.value || ''}\n\`\`\``
      };

    case 'inlineCode':
      return {
        type: 'codespan',
        text: node.value || '',
        raw: '`' + (node.value || '') + '`'
      };

    case 'list':
      return {
        type: 'list',
        ordered: !!node.ordered,
        start: node.start || 1,
        loose: false,
        items: (node.children || []).map((item: any) => ({
          type: 'list_item',
          task: item.checked != null,
          checked: !!item.checked,
          loose: false,
          tokens: convertChildren(item)
        }))
      };

    case 'blockquote':
      return {
        type: 'blockquote',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'table': {
      const rows = node.children || [];
      const headerRow = rows[0] || { children: [] };
      const bodyRows = rows.slice(1);

      return {
        type: 'table',
        header: (headerRow.children || []).map((cell: any) => ({
          text: extractText(cell),
          tokens: convertChildren(cell)
        })),
        rows: bodyRows.map((row: any) =>
          (row.children || []).map((cell: any) => ({
            text: extractText(cell),
            tokens: convertChildren(cell)
          }))
        ),
        align: node.align || []
      };
    }

    case 'thematicBreak':
      return { type: 'hr' };

    case 'html':
      // Keep as raw HTML; renderer handles HtmlToken fallback
      return {
        type: 'html',
        text: node.value || '',
        raw: node.value || ''
      };

    case 'text':
      return {
        type: 'text',
        text: node.value || '',
        raw: node.value || ''
      };

    case 'emphasis':
      return {
        type: 'em',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'strong':
      return {
        type: 'strong',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'link':
      return {
        type: 'link',
        href: node.url || '',
        title: node.title || '',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    case 'image':
      return {
        type: 'image',
        href: node.url || '',
        title: node.title || '',
        text: node.alt || ''
      };

    case 'break':
      return { type: 'br' };

    case 'delete':
      return {
        type: 'del',
        text: extractText(node),
        tokens: convertChildren(node)
      };

    // MATH SUPPORT (remark-math)
    case 'inlineMath':
      return {
        type: 'inlineKatex',
        text: node.value || '',
        displayMode: false
      };

    case 'math':
      return {
        type: 'blockKatex',
        text: node.value || '',
        displayMode: true
      };

    default:
      // Unhandled nodes are ignored to avoid breaking renderers
      return null;
  }
}

function convertChildren(node: any): any[] {
  const out: any[] = [];
  const kids: any[] = Array.isArray(node?.children) ? node.children : [];
  for (const child of kids) {
    const t = convertNode(child);
    if (t) out.push(t);
  }
  return out;
}

function extractText(node: any): string {
  if (!node) return '';
  if (typeof node === 'string') return node;
  if (node.value) return String(node.value);
  if (Array.isArray(node.children)) {
    return node.children.map(extractText).join('');
  }
  return '';
}

function countNodes(tree: any): number {
  let count = 0;
  function walk(n: any) {
    if (!n) return;
    count += 1;
    const kids: any[] = Array.isArray(n.children) ? n.children : [];
    for (const c of kids) walk(c);
  }
  walk(tree);
  return count;
}

function analyzeContent(tree: any) {
  const stats = {
    codeBlocks: 0,
    tables: 0,
    lists: 0,
    headings: 0,
    links: 0,
    images: 0,
    inlineMath: 0,
    mathBlocks: 0
  };

  function walk(n: any) {
    if (!n) return;
    switch (n.type) {
      case 'code': stats.codeBlocks++; break;
      case 'table': stats.tables++; break;
      case 'list': stats.lists++; break;
      case 'heading': stats.headings++; break;
      case 'link': stats.links++; break;
      case 'image': stats.images++; break;
      case 'inlineMath': stats.inlineMath++; break;
      case 'math': stats.mathBlocks++; break;
    }
    const kids: any[] = Array.isArray(n.children) ? n.children : [];
    for (const c of kids) walk(c);
  }

  walk(tree);
  return stats;
}
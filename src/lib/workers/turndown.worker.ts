import TurndownService from 'turndown';
import { gfm } from '@joplin/turndown-plugin-gfm';

self.onmessage = async (e) => {
	const { html } = e.data;
	try {
		const turndownService = new TurndownService({
			codeBlockStyle: 'fenced',
			headingStyle: 'atx'
		});
		turndownService.escape = (string) => string;

		turndownService.addRule('singleNewlineParagraphs', {
			filter: 'p',
			replacement: function (content) {
				return '\n' + content + '\n';
			}
		});

		turndownService.use(gfm);

		turndownService.addRule('tableHeaders', {
			filter: 'th',
			replacement: function (content, node) {
				return content;
			}
		});

		turndownService.addRule('tables', {
			filter: 'table',
			replacement: function (content, node) {
				const rows = Array.from(node.querySelectorAll('tr'));
				if (rows.length === 0) return content;

				let markdown = '\n';

				rows.forEach((row, rowIndex) => {
					const cells = Array.from(row.querySelectorAll('th, td'));
					const cellContents = cells.map((cell) => {
						let cellContent = turndownService.turndown(cell.innerHTML).trim();
						cellContent = cellContent.replace(/^\n+|\n+$/g, '');
						return cellContent;
					});

					markdown += '| ' + cellContents.join(' | ') + ' |\n';

					if (rowIndex === 0) {
						const separator = cells.map(() => '---').join(' | ');
						markdown += '| ' + separator + ' |\n';
					}
				});

				return markdown + '\n';
			}
		});

		turndownService.addRule('taskListItems', {
			filter: (node) =>
				node.nodeName === 'LI' &&
				(node.getAttribute('data-checked') === 'true' ||
					node.getAttribute('data-checked') === 'false'),
			replacement: function (content, node) {
				const checked = node.getAttribute('data-checked') === 'true';
				content = content.replace(/^\s+/, '');
				return `- [${checked ? 'x' : ' '}] ${content}\n`;
			}
		});

		turndownService.addRule('mentions', {
			filter: (node) => node.nodeName === 'SPAN' && node.getAttribute('data-type') === 'mention',
			replacement: (_content, node) => {
				const id = node.getAttribute('data-id') || '';
				const ch = node.getAttribute('data-mention-suggestion-char') || '@';
				return `<${ch}${id}>`;
			}
		});

		const markdown = turndownService.turndown(html);
		self.postMessage({ success: true, markdown });
	} catch (error) {
		self.postMessage({ success: false, error: error.message });
	}
};

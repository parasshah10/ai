export const updateFileNameInFilesArray = (files: any[], fileId: string, newFilename: string, newContent?: string) => {
	return files.map((f) => {
		if (f.id === fileId) {
			// Deep clone to ensure reactivity and preserve existing nested data
			const updated = JSON.parse(JSON.stringify(f));

			// Update all potential name fields used in the UI
			updated.name = newFilename;
			if (updated.meta) updated.meta.name = newFilename;
			if (updated.file) {
				updated.file.filename = newFilename;
				updated.file.name = newFilename;

				// If new content is provided (from a save operation), sync it too
				if (newContent !== undefined) {
					if (!updated.file.data) updated.file.data = {};
					updated.file.data.content = newContent;
				}
			}

			// Handle legacy or alternative content paths
			if (newContent !== undefined) {
				if (updated.data) updated.data.content = newContent;
				if (updated.content !== undefined) updated.content = newContent;
			}

			return updated;
		}
		return f;
	});
};

export const updateFileNameInHistory = (
	history: any,
	fileId: string,
	newFilename: string,
	newContent?: string
) => {
	const messages = { ...history.messages };

	Object.keys(messages).forEach((id) => {
		const msg = messages[id];

		// 1. Update Chat Input Attachments
		if (msg.files) {
			msg.files = updateFileNameInFilesArray(msg.files, fileId, newFilename, newContent);
		}

		// 2. Update Source Footers (Citations)
		const updateMetadata = (metadata: any[]) => {
			metadata.forEach((m: any) => {
				if (m.name) m.name = newFilename;
				// Some components use 'source' as a filename string
				if (m.source && m.source !== fileId) {
					m.source = newFilename;
				}
			});
		};

		if (msg.sources) {
			msg.sources.forEach((s: any) => {
				if (s.source?.id === fileId) {
					s.source.name = newFilename;
					if (s.metadata) updateMetadata(s.metadata);
				}
			});
		}

		if (msg.citations) {
			msg.citations.forEach((c: any) => {
				if (c.source?.id === fileId) {
					c.source.name = newFilename;
					if (c.metadata) updateMetadata(c.metadata);
				}
			});
		}
	});

	return messages;
};

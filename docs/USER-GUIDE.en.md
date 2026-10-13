# Galpium User Guide

**English** · [한국어](USER-GUIDE.md) · [日本語](USER-GUIDE.ja.md) ·
[README](../README.md)

Galpium stores organized knowledge as **pages** and preserves the original text
and files behind it as **materials**. Editing a page leaves its original
materials intact. Links between pages and citation footnotes help you return to
the evidence behind your notes.

## Getting started

Follow the [installation instructions in the README](../README.md#install).
The first launch opens an empty wiki.

1. Choose **New Page** and enter a title and body.
2. Choose **Save** or press **⌘S**.
3. Choose **Done** to return to reading.

To start with an existing file, choose **Materials → Add Material → Import
Files…** in the sidebar. In a material's details, **New Page from Material**
opens a new page linked to that material.

Use **My Wiki**, **Materials** and **Archive** in the sidebar to navigate. The
back and forward buttons, **⌘[ / ⌘]**, and macOS page-swipe gestures return to
previous views. Navigation gestures are unavailable while editing.

## Writing pages

Open a page and choose **Edit**. **Create** shows the editor, and **Preview**
shows the rendered page. When the window is wide enough, **Split** shows both
side by side.

![Markdown editing alongside the live preview in Galpium](images/editor.jpg)

*Write Markdown alongside its live preview.*

The **Format** menu inserts headings, lists, quotes, code, links and tables.
Choose **Attach Files**, drop files into the editor, or paste an image from the
clipboard. Under **Page Settings · Sources, Tags & Summary**, set tags, pin the
page, link materials and describe the changes. Separate tags with commas.

**Save** records your changes and keeps the editor open. **Done** saves and
returns to reading. **Back** asks how to handle any unsaved changes.

## Managing materials

**Materials** holds text, PDFs, images, audio and other files. Choose **Add
Material → Add Text…** to preserve copied text, or **Import Files…** to add a
file. You can also drop files onto the materials list. Imported files can be up
to 150 MiB each.

Open a material to read its original text or see a preview. PDFs offer
**Preview / Text**, and audio has a player. **Open** opens a file in an external
app; **Show in Finder** reveals its stored location.

Each material's **…** menu offers rename, archive, restore and delete. Renaming
a file preserves its extension. Original contents cannot be edited in place;
add an updated file as a new material. Click the link count to see pages,
materials, drafts and history that reference it. Materials with remaining
references cannot be deleted.

## Searching

Press **⌘K** to focus the search field. **My Wiki** searches pages, and
**Materials** searches materials. Filter materials by type or narrow page
results by tag.

Search combines keywords with meaning, so a different phrase or a question in
another language can find related items. Text queries can also find visual
content in images and PDF pages, and content in audio segments. A PDF result
opens the matching page; an audio result opens at the start of the matching
segment. Audio does not play automatically.

Indexing runs in the background after content is added. Keyword results remain
available while the index is preparing or semantic search is unavailable.
Archive searches use keywords. Search runs on your Mac with the model included
in the app.

Galpium does not generate OCR text for images or scanned PDFs, or transcripts
for audio. Video indexing is not supported. A similar result does not establish
that it answers your question or contains an exact quotation. Open the original
to check its contents.

## Links and citation footnotes

Choose **More → Copy Link** on a page to copy a `[[page-slug]]` link, then paste
it into another page. **Sources & Backlinks** shows linked materials and pages
that link to the current page.

To quote a passage from a material:

1. Edit the page and expand **Page Settings · Sources, Tags & Summary**.
2. Find the material and choose **Cite…**.
3. Select an original page and copy the exact passage into the quotation field.
4. Choose **Insert Footnote**, then save the page.

A citation footnote can be inserted only when the passage exists in the
original. While reading, click a footnote number to see the quotation and
choose **View Original** to open its location. Saved citations remain intact
after renaming a material or rebuilding the search index. Image and audio
search matches cannot themselves serve as verified quotation passages.

Ordinary explanatory footnotes are also supported.

```markdown
Add a note to a sentence.[^note]

[^note]: Additional explanation.
```

External web links can be opened. External images appear as links and are not
downloaded automatically.

## Preserving the context of AI work

When AI helps organize a page, you can preserve the requested prompt and chat
link in a text material and link it to the page. This records the scope of the
request and lets you return to the original conversation.

The text material's **Source URL · Optional** field accepts a web address or a
`codex://threads/<chat-UUID>` link to an existing local chat. A supported chat
link enables **Open in ChatGPT** in the material's details. Opening it requires
the corresponding desktop app and access to the chat.

## Drafts, history and archive

When you pause typing, Galpium preserves the edits as a local draft. Preserving
a draft is separate from saving a page. On the next launch, open **Saved
Drafts → Recover** and save the recovered page.

If AI or another window changes the same page first, a comparison with the
latest version opens. **Save Draft as New Revision** saves the draft you have
reviewed as a new revision. Earlier content remains in history.

Use **More → History** to compare previous revisions with the current page and
restore one. Restoring creates a new revision with the earlier contents and
preserves existing history. **Archive Page…** moves a page to the archive while
keeping its content and history. The archive's **Pages / Materials** filter
helps you find items to restore.

**Check Wiki Structure** in the settings menu lists broken links, orphan pages,
originals that have not been organized and missing attachments. Check factual accuracy and
interpretation separately by reading the original material.

## Backups and export

Choose **Wiki → Full Backup…** and select a destination. A backup includes
pages, materials, all revision history and original attachments. Keep the
entire backup folder together.

**Import Backup…** adds a backup to the current library. It reuses identical
items already present and does not overwrite local drafts. If an item with the
same identifier has different contents, the import stops rather than
overwriting existing content.

**More → Export Markdown…** saves one page's body to a file. Use a full backup
to preserve internal links, materials, citations and history together.

## Connecting AI

To connect a local chat in ChatGPT desktop, install Galpium and ChatGPT in
**Applications**, then install the plugin.

1. Download and extract the [plugin ZIP](https://github.com/KimEJ/Galpium/releases/download/v0.0.2/Galpium-Codex-Plugin-0.0.2.zip).
2. Open the **Galpium-Codex** folder. It contains **Install Galpium
   Plugin.command**, the **plugin** folder, and **LICENSE** and **NOTICE** files.
3. Double-click **Install Galpium Plugin.command** and wait for **Galpium
   installed.**
4. Quit ChatGPT with **⌘Q**, reopen it, and select **@Galpium** in a new local
   chat.

The installer registers the connection settings. A separate CLI installation
or configuration-file edit is not needed. In the connected chat, ask AI to find
materials, organize related pages or create a new page. The plugin guides AI
to preserve citations and revision history when working with your wiki.

An open book icon in the Mac menu bar indicates a connected MCP client. Its
menu shows clients and activity. If the connection fails, use **Settings → AI
Connection → Test MCP Connection** to check the app's connection, then
reconnect the client.

Storage and search are local. When a connected AI client reads wiki content,
the data-transfer policies of that client and its model provider apply.

### Other MCP clients

For clients that support stdio MCP connections, register the executable below.
Adapt the configuration format to your client.

```json
{
  "mcpServers": {
    "galpium": {
      "command": "/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
    }
  }
}
```

To select another library, add
`"args": ["--library", "/absolute/path/to/library"]`. See the
[portability guide](PORTABILITY.md) for shell use and direct integration.

## Language and library settings

Open **Settings → App Settings…** from the bottom gear menu, or press **⌘,**.
**Language** follows the system language by default; you can choose 한국어,
English or 日本語. Changing it updates the interface and menus without
translating pages or materials.

The default library is `~/Library/Application Support/Galpium/`. Use **Open or
Create Library…** to select an existing library or a new empty folder. The
previous folder remains intact. After switching libraries, reconnect MCP
clients to use the new library. An explicit library path in an MCP configuration
takes precedence.

Make a full backup before updating. If a new search model requires the index
to be rebuilt, pages, originals, citations and history remain intact. See the
[changelog](CHANGELOG.md) for changes by version. Built-in cloud
synchronization is not provided.

Closing the window keeps the app running in the background. Reopen it from the
Dock or **Open Galpium** in the menu bar. Press **⌘Q** to quit.

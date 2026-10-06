# Galpium User Guide

**English** · [한국어](USER-GUIDE.md) · [日本語](USER-GUIDE.ja.md) ·
[README](../README.md)

## Installation and first launch

Place Galpium.app in Applications and open it. The app includes the wiki engine
and MCP executable. Node, Docker and a server account are not required.
The public v0.0.1 distribution targets Apple silicon and macOS 14 or later and
uses an ad-hoc signature. It is not Apple-notarized. If macOS asks you to approve
the app, use **System Settings → Privacy & Security**.

The default library is `~/Library/Application Support/Galpium/`. You can choose
another library in the app's settings.

Your first wiki is empty. Write directly with **New Page**, or use **Import
Sources** to preserve UTF-8 Markdown and text files. Imported files appear in
the materials list. Open a material and choose **New Page from Material** to
start organizing it.

Closing the window keeps the app running in the background. Click Galpium in
the Dock to reopen its main window. **⌘Q** quits the app; a separately running
MCP process can continue using the same library.

## Display language

Choose **System Language / 한국어 / English / 日本語** in **Settings → App
Settings… → Language**. By default, Galpium follows the macOS language order
and falls back to English if none of those languages is available.
Your selection is saved and immediately updates the interface, menus and date
display. It does not translate or change your documents, materials, tags or
revision contents.

## Editing and preservation

**Edit** offers **Create**, **Split** and **Preview** modes. Use **⌘B** for bold
and **⌘I** for italics. The formatting menu provides headings, lists, quotes,
code, links, tables and file attachments. You can also drop files into the
editor or paste an image from the clipboard.

Live preview leaves the text, cursor and Korean input composition intact. Finish
input composition before saving. **⌘S** or **Save** records the page and keeps
the editor open. **Done** saves changes and returns to reading. **Back** checks
for unsaved changes. Switching views or saving preserves the current page's
undo history.

In page settings, enter comma-separated tags and set the pin, sources and change
summary. Linking materials is optional. A page you write directly does not
automatically create a separate original. Preserved original text and file
contents remain unchanged; you can rename materials.

Page bodies have a limit of 64 KiB and original text has a limit of 256 KiB.
When creating a page from a large original, Galpium inserts space for notes and
a source link instead of copying the entire original. File attachments have a
limit of 150 MiB; attachment bytes sent through MCP have a limit of 2 MiB.

## Drafts and conflicts

When you pause typing, Galpium preserves your edit as a local draft. This is
shown separately from saving the page. After quitting, reopen it from **Saved
Drafts → Recover** on the home screen. A draft retains its original base
revision and does not automatically overwrite the latest page.

If the app or AI has already changed the same page, saving stops and shows a
comparison with the latest revision. **Save Draft as New Revision** records
the draft you reviewed over the latest page. Decide after comparing; earlier
versions remain in history. Archiving and restoring also check revisions.

## Reading and navigation

Click anywhere on the **My Wiki**, **Materials** or **Archive** sidebar rows.
Only one destination is active, and hovering highlights a row. Returning to
**My Wiki** clears the archive filter. Home, search, archive and materials
lists also open when you click anywhere on a row, with a smooth hover highlight.

Use the bottom-right gear's **Settings** menu to open **App Settings…**, **AI
Connection** or **Check Wiki Structure**. Access materials from the sidebar.
You can also open app settings with **⌘,**.

Use the top back/forward buttons or **⌘[ / ⌘]** to move through page and original
navigation history. Horizontal swipes follow the macOS page-swipe setting.
Navigation gestures are disabled while editing so they do not interrupt input
or horizontal scrolling. During a swipe, the document follows your fingers and
shows a direction indicator. Cancelling returns it to its starting position;
completing the swipe briefly fades to the previous or next document.

**⌘K** focuses search. Active pages combine keyword search with Korean, English
and Japanese paragraph-level semantic search. You can find related documents
with different wording or a question in another language. Tag and archive-state
filters apply to all results. Readable text and PDF contents in materials also
participate in semantic search. Archived items use keyword search.

EmbeddingGemma is bundled with the app and is not loaded when there are no
documents. After documents are added, paragraph indexing runs in the background
and search requests take priority. Keyword results appear while it gets ready.
The shared worker and model shut down after 60 seconds without search or indexing
work. The app and MCP share the worker when using the same library. Read the
bundled model's terms and licenses under **Model and Open Source Licenses**
in settings.

A similarity score is not evidence that the answer exists in a result. Read the
page and original. The index is derived data that can be rebuilt; it does not
affect the originals or revision history in backups and exports. Keyword search
remains available if the model fails.

`[[page-slug]]` links to a wiki page, and `[Original](source:source-slug)` links
to a source. Use **More → Copy Link** to obtain a page identifier. **Sources &
Backlinks** shows originals and incoming links. Safe HTTP, HTTPS and mail links
can be opened. External images appear as links and are not automatically
downloaded. HTML remains plain source text and is not executed.
Existing local chat links in the form `codex://threads/<chat-UUID>` open in
ChatGPT desktop. App-command links that create chats or change settings cannot
be used as sources.

## History, archive and restore

Use **More → History** to select any revision and compare it with the current
page. Restoring brings the past title, body, sources, tags and pin state into a
new active revision. **Archive Page…** preserves the content, history and
attachments. You can restore it from the archive.

**Check Wiki Structure** lists broken links, orphan pages, originals that have
not been organized and missing attachments. It does not check factual accuracy.

## Materials and footnotes

Manage text, PDFs, images and other files in a single list under **Materials**
in the sidebar. Search at the top matches names and readable contents. Use
**Add Material** to add a file or text, or drop files onto the list. Click a
row to open the material's details. PDFs offer **Preview / Text**, and images
have a thumbnail preview. There is no OCR for images or scanned PDFs; materials
without readable text can be found by name.

Click a reference count to see references from current pages, materials, drafts
and history. The **…** menu offers rename, open in an external app, show in
Finder, archive, restore and delete. Referenced materials cannot be deleted.
Use the archive's **Pages / Materials** filter to restore each type. Renaming
a file preserves its extension.

Link materials in page settings or choose **Cite…**. Select an original page
and an actual passage, then choose **Insert Footnote** to connect a number in
the body with a footnote below the document. A passage absent from the original
cannot be inserted. Click a footnote number to read the quote in a popover, then
use **View Original** to open its location. The return button beside a footnote
jumps back to the citing sentence. Ordinary explanatory footnotes are also
supported. Markdown editing and export retain the `[^ref-id]` / `[^ref-id]: text`
syntax.

Verified footnotes preserve the material ID, original hash, extraction snapshot
ID, page and quoted passage in the revision. The requested prompt and chat link
are stored as a generation record in a separate text material. Enter a web
address or chat deep link in the same **Source URL · Optional** field. For a
local chat source, **Open in ChatGPT** in the material's details returns to the
chat. Web addresses and chat deep links in the record's body are also clickable
without changing the original text.

Quoted passages remain intact after renaming, reindexing and backup restoration.
Verifying that a quote exists does not guarantee a statement's factual accuracy
or the validity of its interpretation.

## Backups and importing

**Wiki → Full Backup** creates a consistent SQLite snapshot, original attachments
and a checksum manifest in a new folder. A failure before completion is not
shown as a completed backup. Keep the entire backup folder together. Copying
only a live database file can miss recent WAL contents, so use the app's backup
function.

**Import Backup** verifies checksums and reuses only items identical to existing
data. The same identifier with different contents stops the import with an
error and leaves the existing wiki unchanged. Pages, originals, history,
attachments and logs are imported; existing local drafts are not overwritten.
You can cancel ongoing file operations. Already preserved original attachments
are not deleted by cancellation or page archiving.

Markdown export preserves the body. Use a Galpium full backup to preserve all
internal page, source and attachment references.

## AI connection

The Galpium book icon in the Mac menu bar shows the current wiki's MCP
connection state and client list. An open book means connected; a closed book
means disconnected. Request activity appears in its menu. **Open Galpium**
reopens the app window after you close it. The menu also offers **AI Connection
Settings** and **Test MCP Connection**. Reconnect MCP clients still running
an older version to enable the current status display.

Open **Settings → AI Connection** for connection information. The Codex plugin
includes the MCP connection settings, so you can connect through the plugin.
For a manual connection, copy the settings into Codex's `config.toml`. With
the app in Applications:

```toml
[mcp_servers.galpium]
command = "/Applications/Galpium.app/Contents/MacOS/galpium-mcp"
```

Add these settings to Codex's `config.toml`. To use another library, specify
`args = ["--library", "/absolute/path/to/library"]`. The plugin combines the same
MCP with a skill for collecting materials, searching, citing footnotes and
updating safely. The format follows the [official OpenAI MCP documentation](https://developers.openai.com/codex/mcp).

To install for local chats in ChatGPT desktop, **extract** the distributed ZIP
and run **Install Galpium Plugin.command**. Install Galpium.app and ChatGPT.app
in Applications first. The installer registers a local marketplace and enables
the plugin using ChatGPT's bundled runtime. A separate Codex CLI installation
or manual `config.toml` edit is not required. Restart ChatGPT after installation
and select **@Galpium** in a new local chat.

**Plugin archive upload** is a separate route for registering a package on a
server. This distribution is for a local marketplace that runs Galpium on your
current Mac. Cloud Chat/Work requires a separate remote MCP connection.
Local marketplace installation follows the [official OpenAI plugin documentation](https://developers.openai.com/plugins/build/plugins#install-a-local-plugin-manually).

When installing from the source repository, use:

```sh
sh scripts/install-plugin.command
```

**Test MCP Connection** starts the actual bundled MCP process and checks
initialization and the list of 21 tools.

Search embeddings use the bundled local model. The connected AI client reads
and organizes materials, and its external data-transfer policy applies. Do not
treat a search result as proof; read the current page and original.

## Selecting and upgrading a library

Use **Open or Create Library…** in settings to choose an existing Galpium folder
or a new empty folder. Your previous folder remains intact. The app and MCP use
the same selection; an explicit library path in an MCP configuration takes
precedence.

Storage formats v1 and v2 are backed up and converted to v3 on first launch.
Original bodies and existing revision snapshots are preserved while the current
page/source relationships and search index are built. A failed conversion rolls
back to the previous format. An older app will not overwrite a library created
by a newer app version.

Completion and information notices close automatically after 4 seconds. A new
notice restarts the timer. Errors stay visible until you click the close button.

/**
 * Otzaria Plugin SDK
 * Version: 1.0.0
 *
 * This script is injected automatically by the Otzaria host into every plugin WebView.
 * You do NOT need to include it manually — it is always available as `window.Otzaria`.
 *
 * Usage:
 *   const result = await Otzaria.call('library.findBooks', { query: 'רמב"ם' });
 *   Otzaria.on('plugin.boot', (payload) => { /* use payload.theme, payload.app ... *\/ });
 *
 * Full documentation: docs/plugin-development-guide.md
 */

// ---------------------------------------------------------------------------
// JSDoc type definitions
// ---------------------------------------------------------------------------

/**
 * @typedef {Object} OtzariaResponse
 * @property {boolean} success
 * @property {*} data
 * @property {{ code: string, message: string }|null} error
 */

/**
 * @typedef {Object} BootPayload
 * @property {{ id: string, version: string }} plugin
 * @property {{ version: string, platform: string, locale: string, textDirection: string }} app
 * @property {ThemePayload} theme
 * @property {string[]} permissions  Permissions listed in the manifest (may include revoked ones — check plugin.permissions_changed to track runtime changes)
 */

/**
 * @typedef {Object} ThemePayload
 * @property {'light'|'dark'} mode
 * @property {{ primary:string, onPrimary:string, secondary:string, onSecondary:string,
 *              surface:string, onSurface:string, surfaceContainerHighest:string,
 *              error:string, onError:string, outline:string }} colorScheme
 * @property {{ fontFamily:string, fontSize:number, lineHeight:number,
 *              commentatorsFontFamily:string, commentatorsFontSize:number }} typography
 */

/**
 * @typedef {Object} BookMeta
 * @property {string} bookId
 * @property {string} title
 * @property {string[]} [topics]
 */

/**
 * @typedef {Object} SearchResult
 * @property {string} book
 * @property {string} text
 * @property {number} index
 */

/**
 * @typedef {Object} TocEntry
 * @property {string} text
 * @property {number} index
 * @property {number} level
 */

/**
 * @typedef {Object} JewishDate
 * @property {number} year
 * @property {number} month
 * @property {number} day
 * @property {string} gregorian  ISO 8601
 */

/**
 * @typedef {Object} CalendarEvent
 * @property {string} id
 * @property {string} title
 * @property {string} date  ISO 8601
 * @property {string} description
 */

/**
 * @typedef {Object} ReaderState
 * @property {string|null} currentBook
 * @property {string|null} currentBookId
 * @property {number}      currentIndex
 * @property {Array<{bookId:string, book:string, index:number}>} openTabs
 */

/**
 * @typedef {Object} PublishedRecord
 * @property {string} type
 * @property {string} scope
 * @property {string} key
 * @property {*}      payload
 */

// ---------------------------------------------------------------------------
// Reference object (documentation only — actual object is injected by host)
// ---------------------------------------------------------------------------

/**
 * The global Otzaria Plugin API.
 * Every method listed here maps to an Otzaria.call() invocation.
 *
 * @namespace Otzaria
 */
const OtzariaPluginSDK = {

  // =========================================================================
  // Core RPC
  // =========================================================================

  /**
   * Call a Host API method.
   *
   * @async
   * @param {string} method  Dot-separated, e.g. 'library.findBooks'
   * @param {Object} [payload={}]
   * @returns {Promise<OtzariaResponse>}
   *
   * @example
   * const res = await Otzaria.call('library.findBooks', { query: 'רמב"ם', limit: 10 });
   * if (res.success) res.data.forEach(b => console.log(b.title));
   */
  call: async function(method, payload) {},

  /**
   * Subscribe to a host event.
   *
   * Built-in events:
   *  - `plugin.boot`                   — {@link BootPayload}, fired once
   *  - `plugin.ready`                  — no payload, fired once
   *  - `theme.changed`                 — {@link ThemePayload}
   *  - `navigation.changed`            — { screen: string }
   *  - `reader.current_book_changed`   — { book: string, index: number }
   *  - `calendar.date_changed`         — { date: string } (ISO 8601)
   *  - `workspace.changed`             — { workspaceId: string }
   *  - `settings.changed`              — { key: string, newValue: * }
   *  - `plugin.permissions_changed`    — { pluginId: string, permission: string, granted: boolean }
   *
   * @param {string}            event
   * @param {function(*):void}  callback
   *
   * @example
   * Otzaria.on('plugin.boot', payload => applyTheme(payload.theme));
   * Otzaria.on('theme.changed', theme => applyTheme(theme));
   */
  on: function(event, callback) {},

  /**
   * Unsubscribe a previously-registered handler.
   * Must pass the exact same function reference used in `on()`.
   *
   * @param {string}   event
   * @param {function} callback
   */
  off: function(event, callback) {},

  // =========================================================================
  // app.*        Permission: app.info.read
  // =========================================================================

  /**
   * Get Otzaria app info (version, platform).
   * @example
   * const { data } = await Otzaria.call('app.getInfo');
   * console.log(data.version); // '5.2.1'
   */
  'app.getInfo': null,

  /**
   * Get the current UI theme (full colorScheme + typography).
   * @example
   * const { data: theme } = await Otzaria.call('app.getTheme');
   * document.body.style.background = theme.colorScheme.surface;
   */
  'app.getTheme': null,

  /**
   * Get the app locale and text direction.
   * @example
   * const { data } = await Otzaria.call('app.getLocale');
   * console.log(data.textDirection); // 'rtl'
   */
  'app.getLocale': null,

  // =========================================================================
  // library.*    Permission: library.books.read / library.content.read
  // =========================================================================

  /**
   * Search books by title.
   * @param {{ query: string, limit?: number }} payload
   * @returns {BookMeta[]}
   * @example
   * const { data } = await Otzaria.call('library.findBooks', { query: 'תנ"ך', limit: 5 });
   */
  'library.findBooks': null,

  /**
   * Get metadata for a specific book.
   * @param {{ bookId: string }} payload
   * @returns {BookMeta|null}
   */
  'library.getBookMetadata': null,

  /**
   * Get the user's recently-opened books.
   * @returns {Array<{ bookId:string, title:string, ref:string }>}
   */
  'library.listRecentBooks': null,

  /**
   * Get book text (paginated, max 5000 chars per call).
   * @param {{ bookId:string, offset?:number, limit?:number, section?:string }} payload
   * @returns {string}
   * @example
   * const { data: text } = await Otzaria.call('library.getBookContent', {
   *   bookId: 'בראשית', offset: 0, limit: 2000
   * });
   */
  'library.getBookContent': null,

  /**
   * Get a book's Table of Contents.
   * @param {{ bookId: string }} payload
   * @returns {TocEntry[]}
   */
  'library.getBookToc': null,

  // =========================================================================
  // search.*     Permission: search.fulltext.read
  // =========================================================================

  /**
   * Full-text search across the library.
   * @param {{ query:string, limit?:number }} payload
   * @returns {SearchResult[]}
   * @example
   * const { data } = await Otzaria.call('search.fullText', {
   *   query: 'ואהבת לרעך כמוך', limit: 20
   * });
   */
  'search.fullText': null,

  // =========================================================================
  // reader.*     Permission: reader.open
  // =========================================================================

  /**
   * Open a book at a position.
   * @param {{ bookId:string, index?:number, searchQuery?:string }} payload
   * @returns {boolean}
   */
  'reader.openBook': null,

  /**
   * Open a book at a named reference (section title).
   * @param {{ bookId:string, ref:string, index?:number }} payload
   * @returns {boolean}
   */
  'reader.openBookAtRef': null,

  /**
   * Get the current reader state (active book, all open tabs).
   * @returns {ReaderState}
   */
  'reader.getCurrentState': null,

  // =========================================================================
  // navigation.* Permission: navigation.write
  // =========================================================================

  /**
   * Navigate to a top-level screen.
   * @param {{ target: 'library'|'reading'|'more'|'settings' }} payload
   * @returns {boolean}
   * @example
   * await Otzaria.call('navigation.goTo', { target: 'library' });
   */
  'navigation.goTo': null,

  // =========================================================================
  // notes.*      Permission: notes.read / notes.write
  // =========================================================================

  /**
   * List notes for a book.
   * @param {{ bookId:string }} payload
   */
  'notes.list': null,

  /** Get a summary of all books that have notes. */
  'notes.getBookNotesSummary': null,

  /**
   * Add a note.
   * @param {{ bookId:string, lineNumber:number, content:string }} payload
   */
  'notes.add': null,

  /**
   * Update a note.
   * @param {{ bookId:string, noteId:string, content:string }} payload
   */
  'notes.update': null,

  /**
   * Delete a note.
   * @param {{ bookId:string, noteId:string }} payload
   */
  'notes.delete': null,

  // =========================================================================
  // ui.*         Permission: ui.feedback
  // =========================================================================

  /**
   * Show an informational snackbar.
   * @param {{ message:string }} payload
   */
  'ui.showMessage': null,

  /** Show a success snackbar. */
  'ui.showSuccess': null,

  /** Show an error snackbar. */
  'ui.showError': null,

  /**
   * Show a two-button confirmation dialog.
   * @param {{ title:string, content:string }} payload
   * @returns {{ confirmed:boolean }}
   * @example
   * const { data } = await Otzaria.call('ui.showConfirm', {
   *   title: 'מחיקה', content: 'האם למחוק?'
   * });
   * if (data.confirmed) { ... }
   */
  'ui.showConfirm': null,

  /**
   * Show a warning dialog (destructive action pattern).
   * @param {{ title:string, content:string, subtitle?:string }} payload
   * @returns {{ confirmed:boolean }}
   */
  'ui.showWarning': null,

  // =========================================================================
  // storage.*    Permission: plugin.storage.read / plugin.storage.write
  // =========================================================================

  /**
   * Read a stored value (JSON-deserialized).
   * @param {{ key:string }} payload
   * @returns {*|null}
   * @example
   * const { data: count } = await Otzaria.call('storage.get', { key: 'visitCount' });
   */
  'storage.get': null,

  /**
   * Store any JSON-serializable value.
   * @param {{ key:string, value:* }} payload
   */
  'storage.set': null,

  /**
   * Delete a stored key.
   * @param {{ key:string }} payload
   */
  'storage.remove': null,

  /** List all stored keys. */
  'storage.list': null,

  // =========================================================================
  // settings.*   Permission: settings.read
  // =========================================================================

  /**
   * Read one allowlisted setting.
   *
   * Allowed keys:
   *   keyDarkMode, keyFollowSystemTheme, keySwatchColor, keyDarkSwatchColor,
   *   keyFontSize, keyFontFamily, keyCommentatorsFontFamily, keyCommentatorsFontSize,
   *   keyLineHeight, keySelectedCity, keyCalendarType, keyShowTeamim,
   *   keyDefaultNikud, keyRemoveNikudFromTanach, keyReplaceHolyNames,
   *   keyLibraryViewMode, keyAlignTabsToRight, keyCopyWithHeaders, keyCopyHeaderFormat
   *
   * @param {{ key:string }} payload
   */
  'settings.get': null,

  /**
   * Read multiple allowlisted settings at once.
   * @param {{ keys:string[] }} payload
   */
  'settings.getMany': null,

  // =========================================================================
  // calendar.*   Permission: calendar.read
  // =========================================================================

  /** Get the currently-selected date (ISO 8601). */
  'calendar.getSelectedDate': null,

  /**
   * Get halachic daily times (zmanim).
   * @returns {Record<string, string>}  map of zman name → time string in HH:mm format (local time)
   *
   * @example
   * const { data: times } = await Otzaria.call('calendar.getDailyTimes');
   * console.log(times.sunrise); // '06:23'
   */
  'calendar.getDailyTimes': null,

  /**
   * Get the Jewish date for the selected day.
   * @returns {JewishDate}
   */
  'calendar.getJewishDate': null,

  /**
   * Get calendar events for a date.
   * @param {{ date?:string }} payload  ISO 8601, defaults to selected date
   * @returns {CalendarEvent[]}
   */
  'calendar.getEvents': null,

  // =========================================================================
  // publishedData.*  Permission: published_data.write
  // =========================================================================

  /**
   * Publish or update a record.
   *
   * Supported types: `calendar.event`, `saved.query`, `note.draft`,
   *                  `reference.link`, `tool.badge`
   *
   * Scope:
   *   `'global'`             visible everywhere
   *   `'workspace:<id>'`     visible only in a specific workspace
   *   `'book:<bookId>'`      visible only when that book is open
   *
   * @param {{ type:string, scope:string, key:string, payload:Object }} args
   * @returns {boolean}
   *
   * @example
   * await Otzaria.call('publishedData.upsert', {
   *   type:    'calendar.event',
   *   scope:   'global',
   *   key:     'myPlugin:sunset:2026-04-05',
   *   payload: {
   *     title:     'שקיעה',
   *     startsAt:  '2026-04-05T19:11:00+03:00',
   *     source:    'לוח שנה הלכתי',
   *     importance: 'high',
   *   },
   * });
   */
  'publishedData.upsert': null,

  /**
   * Remove a previously published record.
   * @param {{ type:string, scope:string, key:string }} args
   */
  'publishedData.remove': null,

  /**
   * List all records published by this plugin.
   * @returns {PublishedRecord[]}
   */
  'publishedData.listOwn': null,
};

// ---------------------------------------------------------------------------
// Export (Node / bundlers — ignored in browser)
// ---------------------------------------------------------------------------
if (typeof module !== 'undefined' && module.exports) {
  module.exports = OtzariaPluginSDK;
}

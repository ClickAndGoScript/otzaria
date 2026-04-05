/**
 * Otzaria Plugin SDK — TypeScript Definitions
 * Version: 1.0.0
 *
 * Provides full type-safety when writing Otzaria plugins in TypeScript.
 *
 * Usage:
 *   Add to tsconfig.json: "include": ["otzaria_plugin.d.ts"]
 *   Or: /// <reference path="./otzaria_plugin.d.ts" />
 *
 * The `Otzaria` global is injected automatically by the host.
 * You do NOT need to import or load any script.
 */

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/** Response envelope returned by every `Otzaria.call()` invocation. */
export interface OtzariaResponse<T = unknown> {
  success: boolean;
  data: T;
  error: { code: string; message: string } | null;
}

export interface ColorScheme {
  primary: string;
  onPrimary: string;
  secondary: string;
  onSecondary: string;
  surface: string;
  onSurface: string;
  surfaceContainerHighest: string;
  error: string;
  onError: string;
  outline: string;
}

export interface Typography {
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  commentatorsFontFamily: string;
  commentatorsFontSize: number;
}

export interface ThemePayload {
  mode: 'light' | 'dark';
  colorScheme: ColorScheme;
  typography: Typography;
}

/** Delivered via `plugin.boot` exactly once, before any user interaction. */
export interface BootPayload {
  plugin: { id: string; version: string };
  app: {
    version: string;
    buildNumber?: string;
    platform: 'windows' | 'linux' | 'macos' | 'android' | 'ios' | string;
    locale: string;
    textDirection: 'ltr' | 'rtl';
  };
  theme: ThemePayload;
  /** Permission strings listed in the plugin manifest.
   *  Note: this reflects the manifest at install time and may include
   *  revoked permissions. Listen to `plugin.permissions_changed` to track
   *  runtime grant/revoke changes. */
  permissions: string[];
}

export interface BookMeta {
  bookId: string;
  title: string;
  topics?: string[];
}

export interface SearchResult {
  book: string;
  text: string;
  index: number;
}

export interface TocEntry {
  text: string;
  index: number;
  level: number;
}

export interface JewishDate {
  year: number;
  month: number;
  day: number;
  /** ISO 8601 Gregorian equivalent */
  gregorian: string;
}

export interface CalendarEvent {
  id: string;
  title: string;
  /** ISO 8601 */
  date: string;
  description: string;
}

export interface ReaderState {
  currentBook: string | null;
  currentBookId: string | null;
  currentIndex: number;
  openTabs: Array<{ bookId: string; book: string; index: number }>;
}

export type PublishedDataType =
  | 'calendar.event'
  | 'saved.query'
  | 'note.draft'
  | 'reference.link'
  | 'tool.badge';

export interface PublishedRecord<TPayload = unknown> {
  type: PublishedDataType;
  /** 'global' | 'workspace:<id>' | 'book:<bookId>' */
  scope: string;
  key: string;
  payload: TPayload;
}

/** Payload shape for a `calendar.event` published record */
export interface CalendarEventPayload {
  title: string;
  /** ISO 8601 */
  startsAt: string;
  /** ISO 8601 (optional) */
  endsAt?: string;
  source: string;
  importance?: 'high' | 'medium' | 'low';
  description?: string;
}

// ---------------------------------------------------------------------------
// Event map
// ---------------------------------------------------------------------------

export interface OtzariaEventMap {
  /** Fired once after the SDK is ready, carries full boot context. */
  'plugin.boot': BootPayload;
  /** Fired once after boot. No payload. */
  'plugin.ready': undefined;
  /** Theme / dark-mode changed. */
  'theme.changed': ThemePayload;
  /** Top-level screen navigation changed. */
  'navigation.changed': { screen: 'library' | 'reading' | 'more' | 'settings' };
  /** Active book in the reader changed. */
  'reader.current_book_changed': { book: string; index: number };
  /** Selected calendar date changed. */
  'calendar.date_changed': { date: string };
  /** Active workspace changed. */
  'workspace.changed': { workspaceId: string };
  /** A whitelisted app setting changed. */
  'settings.changed': { key: string; newValue: unknown };
  /** A single permission was granted or revoked by the user. */
  'plugin.permissions_changed': { pluginId: string; permission: string; granted: boolean };
}

export type NavigationTarget = 'library' | 'reading' | 'more' | 'settings';

// ---------------------------------------------------------------------------
// All valid method strings
// ---------------------------------------------------------------------------

export type OtzariaMethod =
  | 'app.getInfo'
  | 'app.getTheme'
  | 'app.getLocale'
  | 'library.findBooks'
  | 'library.getBookMetadata'
  | 'library.listRecentBooks'
  | 'library.getBookContent'
  | 'library.getBookToc'
  | 'search.fullText'
  | 'reader.openBook'
  | 'reader.openBookAtRef'
  | 'reader.getCurrentState'
  | 'navigation.goTo'
  | 'notes.list'
  | 'notes.getBookNotesSummary'
  | 'notes.add'
  | 'notes.update'
  | 'notes.delete'
  | 'ui.showMessage'
  | 'ui.showSuccess'
  | 'ui.showError'
  | 'ui.showConfirm'
  | 'ui.showWarning'
  | 'storage.get'
  | 'storage.set'
  | 'storage.remove'
  | 'storage.list'
  | 'settings.get'
  | 'settings.getMany'
  | 'calendar.getSelectedDate'
  | 'calendar.getDailyTimes'
  | 'calendar.getJewishDate'
  | 'calendar.getEvents'
  | 'publishedData.upsert'
  | 'publishedData.remove'
  | 'publishedData.listOwn';

// ---------------------------------------------------------------------------
// The global Otzaria object
// ---------------------------------------------------------------------------

export interface OtzariaGlobal {
  /**
   * Call a Host API method.
   *
   * @param method  Dot-separated, e.g. `'library.findBooks'`
   * @param payload Method arguments
   */
  call<T = unknown>(
    method: OtzariaMethod | string,
    payload?: Record<string, unknown>
  ): Promise<OtzariaResponse<T>>;

  /** Subscribe to a host-dispatched event. */
  on<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  on(event: string, callback: (detail: unknown) => void): void;

  /** Unsubscribe. Must use the exact same function reference passed to `on()`. */
  off<K extends keyof OtzariaEventMap>(
    event: K,
    callback: (detail: OtzariaEventMap[K]) => void
  ): void;
  off(event: string, callback: (detail: unknown) => void): void;
}

// ---------------------------------------------------------------------------
// Augment global Window
// ---------------------------------------------------------------------------

declare global {
  interface Window {
    /** Injected automatically into every plugin WebView. */
    Otzaria: OtzariaGlobal;
  }
  const Otzaria: OtzariaGlobal;
}

export {};

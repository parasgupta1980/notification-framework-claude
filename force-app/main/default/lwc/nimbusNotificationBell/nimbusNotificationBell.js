import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LANG from '@salesforce/i18n/lang';
import getSummary from '@salesforce/apex/NotificationInboxController.getSummary';
import listMine from '@salesforce/apex/NotificationInboxController.listMine';
import markRead from '@salesforce/apex/NotificationInboxController.markRead';
import markAllRead from '@salesforce/apex/NotificationInboxController.markAllRead';
import markSeen from '@salesforce/apex/NotificationInboxController.markSeen';
import LBL_TITLE from '@salesforce/label/c.Nimbus_Notif_Bell_Title';
import LBL_UNREAD from '@salesforce/label/c.Nimbus_Notif_Bell_Unread';

const POLL_MS = 5 * 60 * 1000;
const JITTER_MS = 30 * 1000;
const MAX_BACKOFF_MS = 30 * 60 * 1000;
const PAGE_SIZE = 20;

export default class NimbusNotificationBell extends NavigationMixin(LightningElement) {
    @api storeKey;

    unreadCount = 0;
    unreadCapped = false;
    items = [];
    nextCursor;
    hasMore = false;
    isOpen = false;
    isLoading = false;
    hasError = false;

    _timer;
    _failures = 0;
    _visibilityHandler = () => this.onVisibilityChange();
    _keyHandler = (e) => this.onDocumentKey(e);

    connectedCallback() {
        document.addEventListener('visibilitychange', this._visibilityHandler);
        this.refreshSummary();
        this.schedule();
    }

    disconnectedCallback() {
        clearTimeout(this._timer);
        document.removeEventListener('visibilitychange', this._visibilityHandler);
        document.removeEventListener('keydown', this._keyHandler);
    }

    // ---- polling -------------------------------------------------------
    schedule() {
        clearTimeout(this._timer);
        const base = Math.min(POLL_MS * 2 ** this._failures, MAX_BACKOFF_MS);
        const jitter = Math.random() * JITTER_MS;
        this._timer = setTimeout(() => this.poll(), base + jitter);
    }

    async poll() {
        if (document.visibilityState === 'visible') {
            await this.refreshSummary();
        }
        this.schedule();
    }

    onVisibilityChange() {
        if (document.visibilityState === 'visible') {
            this.refreshSummary();
            this.schedule();
        }
    }

    async refreshSummary() {
        try {
            const s = await getSummary({ storeKey: this.storeKey });
            this.unreadCount = s.unreadCount;
            this.unreadCapped = s.unreadCountCapped;
            this._failures = 0;
        } catch (e) {
            this._failures = Math.min(this._failures + 1, 3);
        }
    }

    // ---- tray ----------------------------------------------------------
    async toggle() {
        this.isOpen ? this.close() : await this.open();
    }

    async open() {
        this.isOpen = true;
        document.addEventListener('keydown', this._keyHandler);
        await this.loadFirstPage();
        const cutoff = new Date().toISOString();
        markSeen({ cutoff }).catch(() => {});
    }

    close() {
        this.isOpen = false;
        document.removeEventListener('keydown', this._keyHandler);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => this.refs.button?.focus());
    }

    onDocumentKey(e) {
        if (e.key === 'Escape') {
            this.close();
        }
    }

    async loadFirstPage() {
        this.isLoading = true;
        this.hasError = false;
        try {
            const page = await listMine({ storeKey: this.storeKey, lang: LANG, cursor: null, pageSize: PAGE_SIZE });
            this.items = page.items;
            this.nextCursor = page.nextCursor;
            this.hasMore = page.hasMore;
            await this.refreshSummary();
        } catch (e) {
            this.hasError = true;
        } finally {
            this.isLoading = false;
        }
    }

    async handleLoadMore() {
        this.isLoading = true;
        try {
            const page = await listMine({ storeKey: this.storeKey, lang: LANG, cursor: this.nextCursor, pageSize: PAGE_SIZE });
            this.items = [...this.items, ...page.items];
            this.nextCursor = page.nextCursor;
            this.hasMore = page.hasMore;
        } catch (e) {
            this.hasError = true;
        } finally {
            this.isLoading = false;
        }
    }

    async handleItemSelect(event) {
        const { id, targetUrl, isRead } = event.detail;
        if (!isRead) {
            this.items = this.items.map((i) => (i.id === id ? { ...i, isRead: true } : i));
            this.unreadCount = Math.max(this.unreadCount - 1, 0);
            markRead({ ids: [id] }).catch(() => this.refreshSummary());
        }
        if (targetUrl) {
            this.close();
            this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url: targetUrl } });
        }
    }

    async handleMarkAllRead() {
        const cutoff = new Date().toISOString();
        this.items = this.items.map((i) => ({ ...i, isRead: true }));
        this.unreadCount = 0;
        try {
            await markAllRead({ storeKey: this.storeKey, cutoff });
        } finally {
            this.refreshSummary();
        }
    }

    // ---- view helpers --------------------------------------------------
    get badgeText() {
        return this.unreadCapped ? '99+' : String(this.unreadCount);
    }
    get hasUnread() {
        return this.unreadCount > 0;
    }
    get buttonLabel() {
        return this.hasUnread ? LBL_UNREAD.replace('{0}', this.badgeText) : LBL_TITLE;
    }
    get ariaExpanded() {
        return String(this.isOpen);
    }
}

import { LightningElement, api } from 'lwc';
import LBL_TITLE from '@salesforce/label/c.Nimbus_Notif_Bell_Title';
import LBL_MARK_ALL from '@salesforce/label/c.Nimbus_Notif_Mark_All_Read';
import LBL_EMPTY from '@salesforce/label/c.Nimbus_Notif_Empty';
import LBL_ERROR from '@salesforce/label/c.Nimbus_Notif_Error';
import LBL_RETRY from '@salesforce/label/c.Nimbus_Notif_Retry';
import LBL_MORE from '@salesforce/label/c.Nimbus_Notif_Load_More';
import LBL_LOADING from '@salesforce/label/c.Nimbus_Notif_Loading';

export default class NimbusNotificationTray extends LightningElement {
    @api items = [];
    @api hasMore = false;
    @api isLoading = false;
    @api hasError = false;
    @api hasUnread = false;

    label = { title: LBL_TITLE, markAll: LBL_MARK_ALL, empty: LBL_EMPTY, error: LBL_ERROR, retry: LBL_RETRY, more: LBL_MORE, loading: LBL_LOADING };

    renderedCallback() {
        if (!this._focused) {
            this._focused = true;
            this.refs.panel?.focus();
        }
    }

    get showEmpty() {
        return !this.isLoading && !this.hasError && (!this.items || this.items.length === 0);
    }
    get showList() {
        return this.items && this.items.length > 0;
    }

    handleMarkAll() { this.dispatchEvent(new CustomEvent('markallread')); }
    handleMore() { this.dispatchEvent(new CustomEvent('loadmore')); }
    handleRetry() { this.dispatchEvent(new CustomEvent('retry')); }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    handleSelect(e) {
        e.stopPropagation();
        this.dispatchEvent(new CustomEvent('select', { detail: e.detail }));
    }
}

import { LightningElement, api } from 'lwc';
import LANG from '@salesforce/i18n/lang';
import LBL_UNREAD from '@salesforce/label/c.Nimbus_Notif_Unread_Marker';

export default class NimbusNotificationItem extends LightningElement {
    @api item;
    unreadLabel = LBL_UNREAD;

    get isUnread() {
        return this.item && !this.item.isRead;
    }
    get rowClass() {
        return 'item' + (this.isUnread ? ' item--unread' : '') + (this.item?.unavailable ? ' item--unavailable' : '');
    }
    get isoTime() {
        return this.item?.visibleAt ? new Date(this.item.visibleAt).toISOString() : '';
    }
    get displayTime() {
        if (!this.item?.visibleAt) {
            return '';
        }
        return new Intl.DateTimeFormat(LANG, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(this.item.visibleAt));
    }

    handleClick() {
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: { id: this.item.id, targetUrl: this.item.targetUrl, isRead: !this.isUnread },
                bubbles: false
            })
        );
    }
}

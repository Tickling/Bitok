// Package notify — доменная логика уведомлений Messaging Service (FR-009):
// дедупликация по eventId, тихие часы и расчёт напоминаний о тренировках.
package notify

import (
	"sync"
	"time"
)

// Category — категория уведомления (пользователь управляет ими в настройках).
type Category string

const (
	CategoryBooking     Category = "BOOKING"     // заявки, подтверждения, отмены — критичные
	CategoryReminder    Category = "REMINDER"    // напоминания о тренировке — критичные
	CategoryAchievement Category = "ACHIEVEMENT" // некритичные: уважают тихие часы
	CategoryContent     Category = "CONTENT"     // некритичные
	CategoryChat        Category = "CHAT"
)

// Critical — критичные категории доставляются и в тихие часы.
func (c Category) Critical() bool {
	return c == CategoryBooking || c == CategoryReminder || c == CategoryChat
}

// Preferences — настройки пользователя.
type Preferences struct {
	Enabled               map[Category]bool
	QuietStart, QuietEnd  int // часы локального времени, по умолчанию 23 и 8
	Location              *time.Location
	LocalRemindersEnabled bool // клиент сам ставит локальное напоминание за 2 ч (BR-009.7)
}

// DefaultPreferences — значения по умолчанию.
func DefaultPreferences(loc *time.Location) Preferences {
	return Preferences{
		Enabled: map[Category]bool{
			CategoryBooking: true, CategoryReminder: true, CategoryAchievement: true, CategoryContent: true, CategoryChat: true,
		},
		QuietStart: 23, QuietEnd: 8, Location: loc,
	}
}

// Decision — что делать с уведомлением.
type Decision struct {
	Send   bool
	SendAt time.Time // для отложенных (тихие часы)
	Reason string
}

// Decide применяет настройки категорий и тихие часы (BR-009.1, BR-009.2).
// Запись во входящие (in-app inbox) создаётся всегда, решение касается только push.
func Decide(p Preferences, c Category, now time.Time) Decision {
	if enabled, ok := p.Enabled[c]; ok && !enabled {
		return Decision{Send: false, Reason: "category disabled"}
	}
	if c.Critical() {
		return Decision{Send: true, SendAt: now}
	}
	local := now.In(p.Location)
	if inQuietHours(local.Hour(), p.QuietStart, p.QuietEnd) {
		next := time.Date(local.Year(), local.Month(), local.Day(), p.QuietEnd, 0, 0, 0, p.Location)
		if !next.After(local) {
			next = next.AddDate(0, 0, 1)
		}
		return Decision{Send: true, SendAt: next, Reason: "quiet hours"}
	}
	return Decision{Send: true, SendAt: now}
}

func inQuietHours(hour, start, end int) bool {
	if start > end { // интервал через полночь, например 23–8
		return hour >= start || hour < end
	}
	return hour >= start && hour < end
}

// Reminders — моменты серверных напоминаний о тренировке: за 24 ч и за 2 ч.
// Напоминание за 2 ч не отправляется, если клиент ставит его локально (BR-009.7).
// Напоминания в прошлом отбрасываются.
func Reminders(startsAt, now time.Time, localRemindersEnabled bool) []time.Time {
	var out []time.Time
	for _, before := range []time.Duration{24 * time.Hour, 2 * time.Hour} {
		if before == 2*time.Hour && localRemindersEnabled {
			continue
		}
		if at := startsAt.Add(-before); at.After(now) {
			out = append(out, at)
		}
	}
	return out
}

// Deduplicator — одно событие → максимум одно уведомление на пользователя (BR-009.3).
// В проде — уникальный индекс (user_id, source_event_id) в messaging_db.
type Deduplicator struct {
	mu   sync.Mutex
	seen map[string]struct{}
}

// NewDeduplicator создаёт пустой дедупликатор.
func NewDeduplicator() *Deduplicator { return &Deduplicator{seen: map[string]struct{}{}} }

// First возвращает true, если пара (userID, eventID) встречается впервые.
func (d *Deduplicator) First(userID, eventID string) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	key := userID + "|" + eventID
	if _, ok := d.seen[key]; ok {
		return false
	}
	d.seen[key] = struct{}{}
	return true
}

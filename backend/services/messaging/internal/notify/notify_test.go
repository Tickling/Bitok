package notify

import (
	"sync"
	"testing"
	"time"
)

var msk = time.FixedZone("MSK", 3*3600)

func TestCriticalIgnoresQuietHours(t *testing.T) {
	now := time.Date(2026, 11, 2, 23, 30, 0, 0, msk)
	d := Decide(DefaultPreferences(msk), CategoryBooking, now)
	if !d.Send || !d.SendAt.Equal(now) {
		t.Fatalf("booking push must be immediate, got %+v", d)
	}
}

func TestContentDeferredUntilMorning(t *testing.T) {
	now := time.Date(2026, 11, 2, 23, 30, 0, 0, msk)
	d := Decide(DefaultPreferences(msk), CategoryContent, now)
	want := time.Date(2026, 11, 3, 8, 0, 0, 0, msk)
	if !d.SendAt.Equal(want) {
		t.Fatalf("want %v, got %v", want, d.SendAt)
	}
}

func TestEarlyMorningDeferredSameDay(t *testing.T) {
	now := time.Date(2026, 11, 3, 6, 0, 0, 0, msk)
	d := Decide(DefaultPreferences(msk), CategoryAchievement, now)
	if want := time.Date(2026, 11, 3, 8, 0, 0, 0, msk); !d.SendAt.Equal(want) {
		t.Fatalf("want %v, got %v", want, d.SendAt)
	}
}

func TestDisabledCategory(t *testing.T) {
	p := DefaultPreferences(msk)
	p.Enabled[CategoryContent] = false
	if Decide(p, CategoryContent, time.Now()).Send {
		t.Fatal("disabled category must not be sent")
	}
}

func TestRemindersSkipServer2hWhenLocalEnabled(t *testing.T) {
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, msk)
	starts := time.Date(2026, 11, 5, 18, 0, 0, 0, msk)
	if got := Reminders(starts, now, false); len(got) != 2 {
		t.Fatalf("want 2 reminders, got %d", len(got))
	}
	got := Reminders(starts, now, true)
	if len(got) != 1 || !got[0].Equal(starts.Add(-24*time.Hour)) {
		t.Fatalf("want only 24h reminder, got %v", got)
	}
}

func TestDeduplicatorConcurrent(t *testing.T) {
	d := NewDeduplicator()
	var wg sync.WaitGroup
	var mu sync.Mutex
	sent := 0
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if d.First("ivan", "evt-1") {
				mu.Lock()
				sent++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if sent != 1 {
		t.Fatalf("at-least-once delivery must produce exactly one push, got %d", sent)
	}
}

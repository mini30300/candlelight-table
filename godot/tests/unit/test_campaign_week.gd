extends "res://tests/testing.gd"
## CampaignWeek (CAMPAIGN_SPEC §2.3): week numbers from UTC unix time, ISO labels, the weekly reroll countdown and the
## test clock. The week is the only input of the galaxy roll, so these numbers must never drift.


func test_week_numbers() -> void:
	assert_eq(CampaignWeek.week_of(0), 0, "1 Jan 1970 (a Thursday) is in week 0, which starts on Monday 29 Dec 1969")
	assert_eq(CampaignWeek.start_unix(0), -3 * 86400, "week 0 starts three days before the epoch")
	assert_eq(CampaignWeek.week_of(1794657600), 2967, "Sat 14 Nov 2026 12:00 UTC is week 2967")
	assert_eq(CampaignWeek.start_unix(2968), 1794787200, "week 2968 starts Mon 16 Nov 2026 00:00 UTC")
	for w in [1, 100, 2967, 2968, 5000]:
		assert_eq(CampaignWeek.week_of(CampaignWeek.start_unix(w)), w, "the first second of week %d is in it" % w)
		assert_eq(CampaignWeek.week_of(CampaignWeek.start_unix(w) - 1), w - 1, "the second before week %d is in the week before" % w)


func test_iso_labels() -> void:
	assert_eq(CampaignWeek.iso_label(2967), "2026-W46", "14 Nov 2026 is ISO week 46")
	assert_eq(CampaignWeek.iso_label(CampaignWeek.week_of(1609372800)), "2020-W53", "Thu 31 Dec 2020 is 2020-W53")
	assert_eq(CampaignWeek.iso_label(CampaignWeek.week_of(1609718400)), "2021-W01", "Mon 4 Jan 2021 is 2021-W01")
	assert_eq(CampaignWeek.iso_label(CampaignWeek.week_of(1767225600)), "2026-W01", "Thu 1 Jan 2026 is 2026-W01")
	assert_eq(CampaignWeek.iso_label(CampaignWeek.week_of(1798761600)), "2026-W53", "Fri 1 Jan 2027 is still 2026-W53")


func test_reroll_countdown() -> void:
	assert_eq(CampaignWeek.seconds_to_reroll(1794657600), 129600, "36 h from Saturday noon to Monday 00:00 UTC")
	assert_eq(CampaignWeek.seconds_to_reroll(1794787200), 7 * 86400, "a full week right at the reroll")
	assert_eq(CampaignWeek.split(129600 + 3600 * 5 + 60 * 7), {"d": 1, "h": 17, "m": 7}, "split into days, hours, minutes")
	assert_eq(CampaignWeek.split(-5), {"d": 0, "h": 0, "m": 0}, "negative clamps to zero")


func test_test_clock() -> void:
	var old := CampaignWeek.test_now
	CampaignWeek.test_now = 1794657600
	assert_eq(CampaignWeek.now_unix(), 1794657600, "test_now replaces the wall clock")
	assert_eq(CampaignWeek.current(), 2967, "current() follows test_now")
	CampaignWeek.test_now = -1
	assert_true(CampaignWeek.now_unix() > 1700000000, "without test_now the real UTC clock is read")
	CampaignWeek.test_now = old

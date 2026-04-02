const test = require("node:test");
const assert = require("node:assert/strict");
const { DateTime } = require("luxon");

const {
    normalizeTimeFormat,
    validateTimezone,
    evaluateBranchSchedule,
} = require("./scheduleUtils");

test("normalizeTimeFormat normalizes shorthand time values", () => {
    assert.equal(normalizeTimeFormat("9:0"), "09:00");
    assert.equal(normalizeTimeFormat("09:30"), "09:30");
    assert.equal(normalizeTimeFormat("24:00"), null);
});

test("validateTimezone falls back to UTC for invalid values", () => {
    assert.equal(validateTimezone("Asia/Kolkata"), "Asia/Kolkata");
    assert.equal(validateTimezone(""), "UTC");
    assert.equal(validateTimezone("Mars/Olympus"), "UTC");
});

test("evaluateBranchSchedule keeps overnight shifts open into the next day", () => {
    const now = DateTime.fromISO("2026-04-07T01:00:00", {
        zone: "Asia/Kolkata",
    });
    const previousDay = now.minus({ days: 1 }).weekdayLong.toLowerCase();

    const result = evaluateBranchSchedule(
        {
            timezone: "Asia/Kolkata",
            workingHours: {
                [previousDay]: {
                    isOpen: true,
                    slots: [{ open: "22:00", close: "02:00" }],
                },
            },
        },
        { now }
    );

    assert.equal(result.hasScheduleControl, true);
    assert.equal(result.isScheduledOpen, true);
    assert.equal(result.openReason, "Auto-Opened by Schedule");
});

test("evaluateBranchSchedule fully closed holiday overrides normal schedule", () => {
    const now = DateTime.fromISO("2026-04-07T12:00:00", {
        zone: "Asia/Kolkata",
    });
    const currentDay = now.weekdayLong.toLowerCase();

    const result = evaluateBranchSchedule(
        {
            timezone: "Asia/Kolkata",
            workingHours: {
                [currentDay]: {
                    isOpen: true,
                    slots: [{ open: "09:00", close: "22:00" }],
                },
            },
            holidayClosures: [
                {
                    name: "Eid Closure",
                    date: now.toISODate(),
                    type: "Fully Closed",
                },
            ],
        },
        { now }
    );

    assert.equal(result.isScheduledOpen, false);
    assert.match(result.closedReason, /Holiday Exception/);
});

test("evaluateBranchSchedule uses holiday hour slots when provided", () => {
    const timezone = "Asia/Kolkata";
    const openNow = DateTime.fromISO("2026-04-07T12:00:00", { zone: timezone });
    const closedNow = DateTime.fromISO("2026-04-07T16:00:00", { zone: timezone });

    const data = {
        timezone,
        workingHours: {},
        holidayClosures: [
            {
                name: "Ramadan Hours",
                date: openNow.toISODate(),
                type: "Short Hours",
                slots: [{ open: "10:00", close: "14:00" }],
            },
        ],
    };

    const openResult = evaluateBranchSchedule(data, { now: openNow });
    const closedResult = evaluateBranchSchedule(data, { now: closedNow });

    assert.equal(openResult.hasScheduleControl, true);
    assert.equal(openResult.isScheduledOpen, true);
    assert.match(openResult.openReason, /Holiday Hours/);
    assert.equal(closedResult.isScheduledOpen, false);
    assert.match(closedResult.closedReason, /Outside Holiday Hours/);
});

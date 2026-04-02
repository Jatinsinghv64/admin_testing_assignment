const { DateTime } = require("luxon");

const ORDERED_DAYS = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
];

const MINUTES_PER_DAY = 24 * 60;

function validateTimezone(tz) {
    if (!tz || typeof tz !== "string" || tz.trim() === "") {
        return "UTC";
    }

    const candidate = tz.trim();
    const testDate = DateTime.now().setZone(candidate);
    return testDate.isValid ? candidate : "UTC";
}

function normalizeTimeFormat(timeStr) {
    if (!timeStr || typeof timeStr !== "string") return null;

    const parts = timeStr.split(":");
    if (parts.length !== 2) return null;

    const hours = parseInt(parts[0], 10);
    const minutes = parseInt(parts[1], 10);

    if (
        Number.isNaN(hours) ||
        Number.isNaN(minutes) ||
        hours < 0 ||
        hours > 23 ||
        minutes < 0 ||
        minutes > 59
    ) {
        return null;
    }

    return `${hours.toString().padStart(2, "0")}:${minutes
        .toString()
        .padStart(2, "0")}`;
}

function parseTimeMinutes(timeStr) {
    const normalized = normalizeTimeFormat(timeStr);
    if (!normalized) return null;
    const [hours, minutes] = normalized.split(":").map(Number);
    return (hours * 60) + minutes;
}

function normalizeDayKey(rawDay) {
    if (!rawDay || typeof rawDay !== "string") {
        return null;
    }

    const normalized = rawDay.trim().toLowerCase();
    return ORDERED_DAYS.includes(normalized) ? normalized : null;
}

function calculateSlotDurationMinutes(slot) {
    const open = parseTimeMinutes(slot?.open);
    const close = parseTimeMinutes(slot?.close);

    if (open == null || close == null) {
        return 0;
    }

    let duration = close - open;
    if (duration <= 0) {
        duration += MINUTES_PER_DAY;
    }
    return duration;
}

function buildSlotInterval(slot, dayOffset = 0) {
    const openMinutes = parseTimeMinutes(slot?.open);
    const closeMinutes = parseTimeMinutes(slot?.close);

    if (openMinutes == null || closeMinutes == null) {
        return null;
    }

    const startMinutes = (dayOffset * MINUTES_PER_DAY) + openMinutes;
    let endMinutes = (dayOffset * MINUTES_PER_DAY) + closeMinutes;

    if (closeMinutes <= openMinutes) {
        endMinutes += MINUTES_PER_DAY;
    }

    return { startMinutes, endMinutes };
}

function intervalsOverlap(left, right) {
    return left.startMinutes < right.endMinutes &&
        right.startMinutes < left.endMinutes;
}

function normalizeWorkingHours(rawWorkingHours) {
    const normalizedWorkingHours = {};
    for (const day of ORDERED_DAYS) {
        normalizedWorkingHours[day] = { isOpen: false, slots: [] };
    }

    const issues = [];
    if (!rawWorkingHours || typeof rawWorkingHours !== "object") {
        return {
            workingHours: normalizedWorkingHours,
            issues,
            hasScheduleControl: false,
        };
    }

    let hasScheduleControl = false;

    for (const [rawDay, rawDayData] of Object.entries(rawWorkingHours)) {
        const dayKey = normalizeDayKey(rawDay);
        if (!dayKey) {
            issues.push(`Ignored unknown schedule day "${rawDay}"`);
            continue;
        }

        hasScheduleControl = true;
        const dayData =
            rawDayData && typeof rawDayData === "object" ? rawDayData : {};
        const isOpen = dayData.isOpen === true;
        const rawSlots = Array.isArray(dayData.slots) ? dayData.slots : [];
        const slots = [];

        for (let index = 0; index < rawSlots.length; index++) {
            const rawSlot = rawSlots[index];
            if (!rawSlot || typeof rawSlot !== "object") {
                issues.push(`Ignored invalid slot ${index + 1} on ${dayKey}`);
                continue;
            }

            const normalizedOpen = normalizeTimeFormat(rawSlot.open);
            const normalizedClose = normalizeTimeFormat(rawSlot.close);
            if (!normalizedOpen || !normalizedClose) {
                issues.push(
                    `Ignored invalid time on ${dayKey} slot ${index + 1}`
                );
                continue;
            }

            slots.push({
                ...rawSlot,
                open: normalizedOpen,
                close: normalizedClose,
            });
        }

        slots.sort((left, right) => {
            const leftOpen = parseTimeMinutes(left.open) ?? 0;
            const rightOpen = parseTimeMinutes(right.open) ?? 0;
            if (leftOpen !== rightOpen) {
                return leftOpen - rightOpen;
            }
            return calculateSlotDurationMinutes(left) -
                calculateSlotDurationMinutes(right);
        });

        normalizedWorkingHours[dayKey] = {
            isOpen,
            slots,
        };

        if (isOpen && slots.length === 0) {
            issues.push(`Open day "${dayKey}" has no valid slots`);
        }

        if (isOpen) {
            for (let first = 0; first < slots.length; first++) {
                for (let second = first + 1; second < slots.length; second++) {
                    const leftInterval = buildSlotInterval(slots[first], 0);
                    const rightInterval = buildSlotInterval(slots[second], 0);
                    if (
                        leftInterval &&
                        rightInterval &&
                        intervalsOverlap(leftInterval, rightInterval)
                    ) {
                        issues.push(
                            `${dayKey} slots ${first + 1} and ${second + 1} overlap`
                        );
                    }
                }
            }
        }
    }

    for (let index = 0; index < ORDERED_DAYS.length; index++) {
        const day = ORDERED_DAYS[index];
        const nextDay = ORDERED_DAYS[(index + 1) % ORDERED_DAYS.length];
        const currentDay = normalizedWorkingHours[day];
        const followingDay = normalizedWorkingHours[nextDay];

        if (!currentDay.isOpen || !followingDay.isOpen) {
            continue;
        }

        for (let currentIndex = 0; currentIndex < currentDay.slots.length; currentIndex++) {
            const currentInterval = buildSlotInterval(
                currentDay.slots[currentIndex],
                0
            );

            if (!currentInterval || currentInterval.endMinutes <= MINUTES_PER_DAY) {
                continue;
            }

            for (let nextIndex = 0; nextIndex < followingDay.slots.length; nextIndex++) {
                const nextInterval = buildSlotInterval(
                    followingDay.slots[nextIndex],
                    1
                );

                if (nextInterval && intervalsOverlap(currentInterval, nextInterval)) {
                    issues.push(
                        `${day} slot ${currentIndex + 1} overlaps ${nextDay} slot ${nextIndex + 1}`
                    );
                }
            }
        }
    }

    return {
        workingHours: normalizedWorkingHours,
        issues,
        hasScheduleControl,
    };
}

function parseHolidayDate(rawValue, timezone) {
    if (!rawValue) {
        return null;
    }

    let candidate = rawValue;
    if (candidate && typeof candidate.toDate === "function") {
        try {
            candidate = candidate.toDate();
        } catch (error) {
            candidate = rawValue;
        }
    }

    let parsed;
    if (candidate instanceof Date) {
        parsed = DateTime.fromJSDate(candidate, { zone: timezone });
    } else if (typeof candidate === "string") {
        parsed = DateTime.fromISO(candidate, { zone: timezone });
        if (!parsed.isValid) {
            parsed = DateTime.fromRFC2822(candidate, { zone: timezone });
        }
    } else if (typeof candidate === "number") {
        parsed = DateTime.fromMillis(candidate, { zone: timezone });
    } else if (typeof candidate === "object" && candidate !== null) {
        if (typeof candidate.seconds === "number") {
            parsed = DateTime.fromSeconds(candidate.seconds, { zone: timezone });
        } else if (typeof candidate._seconds === "number") {
            parsed = DateTime.fromSeconds(candidate._seconds, { zone: timezone });
        }
    }

    if (!parsed || !parsed.isValid) {
        return null;
    }

    return parsed.startOf("day");
}

function normalizeHolidayType(rawType) {
    if (!rawType || typeof rawType !== "string") {
        return "custom";
    }

    const normalized = rawType.trim().toLowerCase().replace(/[_-]+/g, " ");
    if (normalized.includes("fully") || normalized.includes("closed")) {
        return "fully_closed";
    }
    if (normalized.includes("short")) {
        return "short_hours";
    }
    if (normalized.includes("special")) {
        return "special_event";
    }
    return "custom";
}

function normalizeHolidayClosures(rawHolidayClosures, timezone) {
    const issues = [];
    if (!Array.isArray(rawHolidayClosures)) {
        return { holidays: [], issues };
    }

    const holidays = [];

    for (let index = 0; index < rawHolidayClosures.length; index++) {
        const rawHoliday = rawHolidayClosures[index];
        if (!rawHoliday || typeof rawHoliday !== "object") {
            issues.push(`Ignored invalid holiday exception ${index + 1}`);
            continue;
        }

        const startDate = parseHolidayDate(
            rawHoliday.date ?? rawHoliday.startDate,
            timezone
        );
        const endDate = parseHolidayDate(
            rawHoliday.endDate ?? rawHoliday.untilDate ?? rawHoliday.date,
            timezone
        ) ?? startDate;

        if (!startDate || !endDate) {
            issues.push(`Ignored holiday exception ${index + 1} with invalid date`);
            continue;
        }

        const type = normalizeHolidayType(rawHoliday.type);
        const slots = [];
        if (Array.isArray(rawHoliday.slots)) {
            for (const slot of rawHoliday.slots) {
                const normalizedOpen = normalizeTimeFormat(slot?.open);
                const normalizedClose = normalizeTimeFormat(slot?.close);
                if (normalizedOpen && normalizedClose) {
                    slots.push({ ...slot, open: normalizedOpen, close: normalizedClose });
                }
            }
        } else if (rawHoliday.open && rawHoliday.close) {
            const normalizedOpen = normalizeTimeFormat(rawHoliday.open);
            const normalizedClose = normalizeTimeFormat(rawHoliday.close);
            if (normalizedOpen && normalizedClose) {
                slots.push({ open: normalizedOpen, close: normalizedClose });
            }
        }

        if (type === "short_hours" && slots.length === 0) {
            issues.push(
                `Holiday exception "${rawHoliday.name || index + 1}" is short hours without slots`
            );
        }

        holidays.push({
            ...rawHoliday,
            name:
                typeof rawHoliday.name === "string" && rawHoliday.name.trim()
                    ? rawHoliday.name.trim()
                    : null,
            type,
            dateKey: startDate.toISODate(),
            endDateKey: endDate.toISODate(),
            slots,
            forceClosed:
                rawHoliday.forceClosed === true || type === "fully_closed",
            forceOpen:
                rawHoliday.forceOpen === true ||
                (type === "special_event" && rawHoliday.isOpenAllDay === true),
        });
    }

    return { holidays, issues };
}

function isWithinSlot(now, openStr, closeStr, timezone, dayOffset) {
    try {
        const normalizedOpen = normalizeTimeFormat(openStr);
        const normalizedClose = normalizeTimeFormat(closeStr);

        if (!normalizedOpen || !normalizedClose) {
            return { isWithin: false };
        }

        const baseDate = now.plus({ days: dayOffset });

        let openTime = DateTime.fromFormat(normalizedOpen, "HH:mm", { zone: timezone })
            .set({
                year: baseDate.year,
                month: baseDate.month,
                day: baseDate.day,
            });

        let closeTime = DateTime.fromFormat(normalizedClose, "HH:mm", { zone: timezone })
            .set({
                year: baseDate.year,
                month: baseDate.month,
                day: baseDate.day,
            });

        if (closeTime <= openTime) {
            closeTime = closeTime.plus({ days: 1 });
        }

        return {
            isWithin: now >= openTime && now < closeTime,
            openTime,
            closeTime,
        };
    } catch (error) {
        return { isWithin: false };
    }
}

function getHolidayOverride(now, holidayClosures, timezone) {
    const todayKey = now.toISODate();
    const activeHolidays = holidayClosures.filter((holiday) =>
        todayKey >= holiday.dateKey && todayKey <= holiday.endDateKey
    );

    if (activeHolidays.length === 0) {
        return null;
    }

    const namedSuffix = (holiday) => holiday?.name ? `: ${holiday.name}` : "";

    const fullyClosed = activeHolidays.find((holiday) => holiday.forceClosed);
    if (fullyClosed) {
        return {
            type: "fully_closed",
            isScheduledOpen: false,
            openReason: "Auto-Opened by Schedule",
            closedReason: `Auto-Closed by Holiday Exception${namedSuffix(fullyClosed)}`,
            activeHoliday: fullyClosed,
        };
    }

    const slotOverrides = activeHolidays.filter((holiday) => holiday.slots.length > 0);
    if (slotOverrides.length > 0) {
        const mergedSlots = slotOverrides.flatMap((holiday) => holiday.slots);
        const isScheduledOpen = mergedSlots.some((slot) =>
            isWithinSlot(now, slot.open, slot.close, timezone, 0).isWithin
        );
        const labelHoliday = slotOverrides[0];
        return {
            type: "holiday_hours",
            isScheduledOpen,
            openReason: `Auto-Opened by Holiday Hours${namedSuffix(labelHoliday)}`,
            closedReason: `Auto-Closed Outside Holiday Hours${namedSuffix(labelHoliday)}`,
            activeHoliday: labelHoliday,
        };
    }

    const specialOpen = activeHolidays.find((holiday) => holiday.forceOpen);
    if (specialOpen) {
        return {
            type: "special_event",
            isScheduledOpen: true,
            openReason: `Auto-Opened by Special Event${namedSuffix(specialOpen)}`,
            closedReason: "Auto-Closed by Schedule",
            activeHoliday: specialOpen,
        };
    }

    return null;
}

function evaluateBranchSchedule(data, options = {}) {
    const timezone = validateTimezone(data?.timezone || "UTC");
    const schedule = normalizeWorkingHours(data?.workingHours);
    const holidays = normalizeHolidayClosures(data?.holidayClosures, timezone);

    let now;
    if (DateTime.isDateTime(options.now)) {
        now = options.now.setZone(timezone);
    } else if (options.now instanceof Date) {
        now = DateTime.fromJSDate(options.now, { zone: timezone });
    } else {
        now = DateTime.now().setZone(timezone);
    }

    const holidayOverride = getHolidayOverride(now, holidays.holidays, timezone);

    let isScheduledOpen = false;
    let openReason = "Auto-Opened by Schedule";
    let closedReason = "Auto-Closed by Schedule";

    if (holidayOverride) {
        isScheduledOpen = holidayOverride.isScheduledOpen;
        openReason = holidayOverride.openReason;
        closedReason = holidayOverride.closedReason;
    } else if (schedule.hasScheduleControl) {
        const currentDayName = now.weekdayLong.toLowerCase();
        const todaySchedule = schedule.workingHours[currentDayName];

        if (todaySchedule?.isOpen === true && Array.isArray(todaySchedule.slots)) {
            for (const slot of todaySchedule.slots) {
                if (isWithinSlot(now, slot.open, slot.close, timezone, 0).isWithin) {
                    isScheduledOpen = true;
                    break;
                }
            }
        }

        if (!isScheduledOpen) {
            const yesterday = now.minus({ days: 1 });
            const yesterdayName = yesterday.weekdayLong.toLowerCase();
            const yesterdaySchedule = schedule.workingHours[yesterdayName];

            if (
                yesterdaySchedule?.isOpen === true &&
                Array.isArray(yesterdaySchedule.slots)
            ) {
                for (const slot of yesterdaySchedule.slots) {
                    if (isWithinSlot(now, slot.open, slot.close, timezone, -1).isWithin) {
                        isScheduledOpen = true;
                        break;
                    }
                }
            }
        }
    }

    return {
        timezone,
        now,
        isScheduledOpen,
        hasScheduleControl: schedule.hasScheduleControl || holidayOverride !== null,
        openReason,
        closedReason,
        holidayOverride,
        issues: [...schedule.issues, ...holidays.issues],
        normalizedWorkingHours: schedule.workingHours,
        normalizedHolidayClosures: holidays.holidays,
    };
}

module.exports = {
    ORDERED_DAYS,
    normalizeTimeFormat,
    validateTimezone,
    isWithinSlot,
    normalizeWorkingHours,
    normalizeHolidayClosures,
    evaluateBranchSchedule,
    calculateSlotDurationMinutes,
};

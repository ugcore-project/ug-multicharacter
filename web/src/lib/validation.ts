/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// The server's creation rules, for live feedback. A convenience only: the server checks everything again.
// MUST stay in step with server/characters.lua.

import { FieldType, type FormField } from "@/types/protocol";

/** Why a value is refused, as a label key. */
export type FieldError = "required" | "length" | "symbols" | "spaces" | "date" | "age" | "option";

// Digits and symbols. Letters of every language, spaces, apostrophes and hyphens pass.
const NAME_SYMBOLS = /[\d<>{}[\]\\/@#$%^&*=+|~`"!?;:,._()]/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

function isLeap(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

/** Whole years from a birth date to today, or undefined for an impossible date. */
export function ageOn(value: string, today: Date): number | undefined {
  const match = DATE.exec(value);

  if (!match) {
    return undefined;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const days = [31, isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];

  if (days === undefined || day < 1 || day > days) {
    return undefined;
  }

  const todayMonth = today.getMonth() + 1;
  const todayDay = today.getDate();

  return today.getFullYear() - year - (todayMonth < month || (todayMonth === month && todayDay < day) ? 1 : 0);
}

/** The first rule a value breaks, or undefined when it passes. */
export function checkField(field: FormField, value: string, ageRange: { min: number; max: number }, today = new Date()): FieldError | undefined {
  if (value === "") {
    return "required";
  }

  if (field.type === FieldType.Text) {
    const length = [...value].length;

    if (value !== value.trim() || /\s\s/.test(value)) {
      return "spaces";
    }

    if (NAME_SYMBOLS.test(value)) {
      return "symbols";
    }

    if (length < (field.min ?? 1) || length > (field.max ?? 64)) {
      return "length";
    }

    return undefined;
  }

  if (field.type === FieldType.Date) {
    const age = ageOn(value, today);

    if (age === undefined) {
      return "date";
    }

    return age < ageRange.min || age > ageRange.max ? "age" : undefined;
  }

  return field.options?.some((option) => option.value === value) ? undefined : "option";
}

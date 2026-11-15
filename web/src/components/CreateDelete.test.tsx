/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { act, fireEvent, render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "@/App";
import { ageOn, checkField } from "@/lib/validation";
import { DEFAULT_CONFIG, DEFAULT_LABELS, handleMessage, useSceneStore } from "@/store/sceneStore";
import { FieldType, NuiAction, Screen, type FormField } from "@/types/protocol";

const nui = vi.hoisted(() => ({
  sendReady: vi.fn(),
  sendHover: vi.fn(),
  sendSelect: vi.fn(),
  sendSkip: vi.fn(),
  sendModel: vi.fn(),
  sendSubmit: vi.fn(),
  sendCancel: vi.fn(),
  sendDelete: vi.fn(),
  isEnvBrowser: () => false,
}));

vi.mock("@/lib/nui", () => nui);

const FIELDS: FormField[] = [
  { name: "firstName", type: FieldType.Text, label: "First name", min: 2, max: 24 },
  { name: "lastName", type: FieldType.Text, label: "Last name", min: 2, max: 24 },
  { name: "birthDate", type: FieldType.Date, label: "Birth date" },
  { name: "sex", type: FieldType.Select, label: "Sex", options: [{ value: "male", label: "Male" }, { value: "female", label: "Female" }] },
];

const TODAY = new Date(2026, 9, 10);

beforeEach(() => {
  for (const fn of Object.values(nui)) {
    if (typeof fn === "function" && "mockReset" in fn) {
      fn.mockReset();
    }
  }

  useSceneStore.setState({
    config: DEFAULT_CONFIG,
    slots: [],
    focus: 1,
    screen: null,
    visible: true,
    result: null,
    dialogOpen: false,
  });
});

function sendForm(allowDelete = true) {
  handleMessage({
    action: NuiAction.Form,
    payload: { fields: FIELDS, ageRange: { min: 18, max: 90 }, models: ["mp_m_freemode_01", "mp_f_freemode_01"], allowDelete },
  });
}

describe("validation mirrors the server", () => {
  const text = FIELDS[0]!;
  const date = FIELDS[2]!;
  const range = { min: 18, max: 90 };

  it("accepts names of every language and refuses digits, symbols and extra spaces", () => {
    expect(checkField(text, "João", range)).toBeUndefined();
    expect(checkField(text, "O'Neil-Costa", range)).toBeUndefined();
    expect(checkField(text, "Ana2", range)).toBe("symbols");
    expect(checkField(text, "Sil<va>", range)).toBe("symbols");
    expect(checkField(text, "Ana  Maria", range)).toBe("spaces");
    expect(checkField(text, " Ana", range)).toBe("spaces");
    expect(checkField(text, "A", range)).toBe("length");
    expect(checkField(text, "", range)).toBe("required");
  });

  it("counts the age to the day and refuses impossible dates", () => {
    expect(ageOn("2008-10-10", TODAY)).toBe(18);
    expect(ageOn("2008-10-11", TODAY)).toBe(17);
    expect(ageOn("1995-02-30", TODAY)).toBeUndefined();
    expect(ageOn("2000-02-29", TODAY)).toBe(26);
    expect(checkField(date, "2010-01-01", range, TODAY)).toBe("age");
    expect(checkField(date, "12/04/1995", range, TODAY)).toBe("date");
  });

  it("takes only configured options", () => {
    expect(checkField(FIELDS[3]!, "female", range)).toBeUndefined();
    expect(checkField(FIELDS[3]!, "robot", range)).toBe("option");
  });
});

describe("create", () => {
  function openCreate() {
    const view = render(<App />);

    act(() => {
      sendForm();
      handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Create } });
    });

    return view;
  }

  it("shows errors only after a submit, and sends nothing while invalid", () => {
    const { getByRole, queryAllByRole } = openCreate();

    expect(queryAllByRole("alert")).toHaveLength(0);

    fireEvent.click(getByRole("button", { name: "Create" }));

    expect(nui.sendSubmit).not.toHaveBeenCalled();
    expect(queryAllByRole("alert").length).toBe(4);
  });

  it("submits the fields and the chosen body, and previews the body", () => {
    const { getByLabelText, getByRole } = openCreate();

    fireEvent.change(getByLabelText("First name"), { target: { value: "Ana" } });
    fireEvent.change(getByLabelText("Last name"), { target: { value: "Silva" } });
    fireEvent.change(getByLabelText("Birth date"), { target: { value: "1995-04-12" } });
    fireEvent.click(getByRole("radiogroup", { name: "Sex" }).querySelectorAll("button")[1]!);

    const bodies = getByRole("radiogroup", { name: "Body" });

    fireEvent.click(bodies.querySelectorAll("button")[1]!);
    expect(nui.sendModel).toHaveBeenCalledWith("mp_f_freemode_01");

    fireEvent.click(getByRole("button", { name: "Create" }));
    expect(nui.sendSubmit).toHaveBeenCalledWith(
      { firstName: "Ana", lastName: "Silva", birthDate: "1995-04-12", sex: "female" },
      "mp_f_freemode_01",
    );
  });

  it("unlocks the form without an alert when the appearance step was cancelled", () => {
    const { getByLabelText, getByRole, queryAllByRole } = openCreate();

    fireEvent.change(getByLabelText("First name"), { target: { value: "Ana" } });
    fireEvent.change(getByLabelText("Last name"), { target: { value: "Silva" } });
    fireEvent.change(getByLabelText("Birth date"), { target: { value: "1995-04-12" } });
    fireEvent.click(getByRole("radiogroup", { name: "Sex" }).querySelectorAll("button")[1]!);
    fireEvent.click(getByRole("button", { name: "Create" }));
    expect(nui.sendSubmit).toHaveBeenCalledTimes(1);

    act(() => handleMessage({ action: NuiAction.Result, payload: { kind: "create", ok: false } }));
    expect(queryAllByRole("alert")).toHaveLength(0);
    expect((getByLabelText("First name") as HTMLInputElement).value).toBe("Ana");

    fireEvent.click(getByRole("button", { name: "Create" }));
    expect(nui.sendSubmit).toHaveBeenCalledTimes(2);
  });

  it("shows a refusal from the server and lets the player go back", () => {
    const { getByRole, getByText } = openCreate();

    act(() => handleMessage({ action: NuiAction.Result, payload: { kind: "create", ok: false, error: "no_permission" } }));
    expect(getByText("This is not allowed.")).toBeTruthy();

    fireEvent.click(getByRole("button", { name: "Back" }));
    expect(nui.sendCancel).toHaveBeenCalledTimes(1);

    fireEvent.keyDown(window, { key: "Escape" });
    expect(nui.sendCancel).toHaveBeenCalledTimes(2);
  });
});

describe("delete", () => {
  function openSelection(allowDelete = true) {
    const view = render(<App />);

    act(() => {
      sendForm(allowDelete);
      handleMessage({ action: NuiAction.Open, payload: { slots: [{ character: { name: "Ana Silva", deathState: "Alive" } }, {}] } });
      handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Select } });
    });

    return view;
  }

  it("needs the exact name, and the arrows do nothing while the dialog is open", () => {
    const { getByRole } = openSelection();

    fireEvent.click(getByRole("button", { name: "Delete" }));

    const dialog = getByRole("dialog");
    const confirm = dialog.querySelector("button[type=submit]") as HTMLButtonElement;
    const input = dialog.querySelector("input") as HTMLInputElement;

    fireEvent.keyDown(window, { key: "ArrowRight" });
    expect(nui.sendHover).not.toHaveBeenCalled();

    fireEvent.change(input, { target: { value: "ana silva" } });
    expect(confirm.disabled).toBe(true);

    fireEvent.change(input, { target: { value: "Ana Silva" } });
    expect(confirm.disabled).toBe(false);

    fireEvent.click(confirm);
    expect(nui.sendDelete).toHaveBeenCalledWith(1);

    act(() => handleMessage({ action: NuiAction.Result, payload: { kind: "delete", ok: true } }));
    expect(() => getByRole("dialog")).toThrow();
  });

  it("has no delete button when the owner turned deleting off", () => {
    const { queryByRole } = openSelection(false);

    expect(queryByRole("button", { name: "Delete" })).toBeNull();
  });
});

it("locales/en.json has exactly the page's labels", () => {
  const file = JSON.parse(readFileSync(path.resolve(import.meta.dirname, "../../../locales/en.json"), "utf8")) as { page: Record<string, string> };

  expect(Object.keys(file.page).sort()).toEqual(Object.keys(DEFAULT_LABELS).sort());

  for (const [key, value] of Object.entries(DEFAULT_LABELS)) {
    expect(file.page[key], key).toBe(value);
  }
});

it("every locale has the same keys as locales/en.json", () => {
  const folder = path.resolve(import.meta.dirname, "../../../locales");
  const keysOf = (value: unknown, prefix = ""): string[] =>
    typeof value === "object" && value !== null
      ? Object.entries(value).flatMap(([key, inner]) => keysOf(inner, prefix + key + "."))
      : [prefix];
  const english = keysOf(JSON.parse(readFileSync(path.join(folder, "en.json"), "utf8"))).sort();

  for (const name of readdirSync(folder).filter((file) => file.endsWith(".json"))) {
    expect(keysOf(JSON.parse(readFileSync(path.join(folder, name), "utf8"))).sort(), name).toEqual(english);
  }
});

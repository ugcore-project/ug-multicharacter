/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { act, fireEvent, render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import App from "@/App";
import { fill, formatBirthDate, initials } from "@/lib/format";
import { DEFAULT_CONFIG, DEFAULT_LABELS, DEFAULT_LAYOUT, handleMessage, readDetails, readLayout, readSlots, useSceneStore } from "@/store/sceneStore";
import { toneShades } from "@/lib/theme";
import { NuiAction, Screen } from "@/types/protocol";

const nui = vi.hoisted(() => ({
  sendReady: vi.fn(),
  sendHover: vi.fn(),
  sendSelect: vi.fn(),
  sendSkip: vi.fn(),
  isEnvBrowser: () => false,
}));

vi.mock("@/lib/nui", () => nui);

const SLOTS = [
  { character: { name: "Ana Silva", birthDate: "1995-04-12", lastPlayed: 1_791_400_000, street: "Vespucci Boulevard", deathState: "Alive" } },
  { character: { name: "Rui Costa", deathState: "Dead" } },
  {},
];

function openSelection() {
  act(() => {
    handleMessage({ action: NuiAction.Open, payload: { slots: SLOTS } });
    handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Select } });
    handleMessage({ action: NuiAction.Visible, payload: { visible: true } });
  });
}

beforeEach(() => {
  for (const fn of [nui.sendReady, nui.sendHover, nui.sendSelect, nui.sendSkip]) {
    fn.mockReset();
  }

  useSceneStore.setState({
    config: DEFAULT_CONFIG,
    slots: [],
    focus: 1,
    screen: null,
    title: { text: "", visible: false },
    visible: false,
  });
});

describe("messages", () => {
  it("rebuilds slots from known fields and drops anything else", () => {
    const slots = readSlots([
      { character: { name: "Ana", deathState: "Alive", extra: "<img>", lastPlayed: "yesterday" } },
      { character: { name: "", deathState: "Alive" } },
      "garbage",
      { character: { name: "Rui", deathState: "Exploded" } },
    ]);

    expect(slots).toEqual([
      { index: 1, character: { name: "Ana", deathState: "Alive" } },
      { index: 2 },
      { index: 3 },
      { index: 4, character: { name: "Rui", deathState: "Alive" } },
    ]);
  });

  it("ignores malformed messages and out-of-range focus", () => {
    openSelection();

    act(() => {
      handleMessage("nope");
      handleMessage({ action: "unknown" });
      handleMessage({ action: NuiAction.Focus, payload: { index: 9 } });
      handleMessage({ action: NuiAction.Focus, payload: { index: 1.5 } });
    });

    expect(useSceneStore.getState().focus).toBe(1);

    act(() => handleMessage({ action: NuiAction.Focus, payload: { index: 2 } }));
    expect(useSceneStore.getState().focus).toBe(2);
  });

  it("keeps default labels for missing or empty ones", () => {
    act(() => handleMessage({ action: NuiAction.Config, payload: { labels: { play: "Jogar", create: "", unknown: "x" }, locale: "pt-PT" } }));

    const { labels, locale } = useSceneStore.getState().config;

    expect(labels.play).toBe("Jogar");
    expect(labels.create).toBe(DEFAULT_LABELS.create);
    expect(labels.unknown).toBeUndefined();
    expect(locale).toBe("pt-PT");
  });
});

describe("selection", () => {
  it("shows the focused character and plays it on click", () => {
    const { getByText, getByRole } = render(<App />);

    openSelection();

    expect(getByText("Vespucci Boulevard")).toBeTruthy();
    expect(getByText("Slot 1 of 3")).toBeTruthy();

    fireEvent.click(getByRole("button", { name: "Play" }));
    expect(nui.sendSelect).toHaveBeenCalledWith(1);
  });

  it("moves with the arrows, wraps around, and hovers with the mouse", () => {
    const { getByRole, getAllByRole } = render(<App />);

    openSelection();

    fireEvent.keyDown(window, { key: "ArrowLeft" });
    expect(nui.sendHover).toHaveBeenLastCalledWith(3);
    expect(getByRole("button", { name: "Create character" })).toBeTruthy();

    fireEvent.keyDown(window, { key: "ArrowRight" });
    fireEvent.keyDown(window, { key: "ArrowRight" });
    expect(nui.sendHover).toHaveBeenLastCalledWith(2);

    fireEvent.keyDown(window, { key: "Enter" });
    expect(nui.sendSelect).toHaveBeenLastCalledWith(2);

    fireEvent.mouseEnter(getAllByRole("option")[0]!);
    expect(nui.sendHover).toHaveBeenLastCalledWith(1);
  });

  it("marks downed and dead characters", () => {
    const { getByText } = render(<App />);

    openSelection();
    act(() => handleMessage({ action: NuiAction.Focus, payload: { index: 2 } }));

    expect(getByText("Dead")).toBeTruthy();
    expect(getByText("Never")).toBeTruthy();
  });
});

describe("intro", () => {
  it("shows the title and skips on Enter or Escape", () => {
    const { getByText } = render(<App />);

    act(() => {
      handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Intro } });
      handleMessage({ action: NuiAction.Title, payload: { text: "Los Santos RP", visible: true } });
    });

    expect(getByText("Los Santos RP")).toBeTruthy();

    fireEvent.keyDown(window, { key: "Escape" });
    expect(nui.sendSkip).toHaveBeenCalledTimes(1);
    expect(nui.sendSelect).not.toHaveBeenCalled();
  });
});

describe("owner config", () => {
  function configure(owner: Record<string, unknown>) {
    act(() => handleMessage({ action: NuiAction.Config, payload: { labels: DEFAULT_LABELS, locale: "en", ...owner } }));
  }

  it("moves the panel and the slot bar, and drops the hint and initials", () => {
    const { container, queryByText } = render(<App />);

    configure({ layout: { side: "right", slots: "top", hint: false, initials: false } });
    openSelection();

    expect(container.querySelector("[data-panel]")?.className).toContain("right-16");
    expect(container.querySelector("[data-slots]")?.className).toContain("top-[8%]");
    expect(container.querySelector("[data-hint]")).toBeNull();
    expect(queryByText("AS")).toBeNull();
  });

  it("shows the owner's details in order, or none", () => {
    const { container, queryByText } = render(<App />);

    configure({ details: ["location", "born"] });
    openSelection();

    const text = container.querySelector("[data-details]")?.textContent ?? "";

    expect(text.indexOf("Vespucci Boulevard")).toBeLessThan(text.indexOf("Born"));
    expect(queryByText("Last played")).toBeNull();

    configure({ details: [] });
    expect(container.querySelector("[data-details]")).toBeNull();
  });

  it("ignores the keys when the owner turned the keyboard off", () => {
    render(<App />);
    configure({ layout: { keyboard: false } });
    openSelection();

    fireEvent.keyDown(window, { key: "ArrowLeft" });
    fireEvent.keyDown(window, { key: "Enter" });
    expect(nui.sendHover).not.toHaveBeenCalled();
    expect(nui.sendSelect).not.toHaveBeenCalled();
  });

  it("hides the skip line and ignores the skip keys when the intro is not skippable", () => {
    const { queryByText } = render(<App />);

    configure({ skippable: false });
    act(() => handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Intro } }));

    expect(queryByText("Press Enter to skip")).toBeNull();
    fireEvent.keyDown(window, { key: "Enter" });
    expect(nui.sendSkip).not.toHaveBeenCalled();
  });

  it("stills the page and recolors an accent with its shades", () => {
    const { container } = render(<App />);

    configure({ layout: { animations: false }, theme: { mode: "dark", colors: { sky: "200 80% 50%" }, radius: "", font: "", scale: 1 } });

    const style = document.documentElement.style;

    expect(container.querySelector("[data-root]")?.className).toContain("ug-still");
    expect(style.getPropertyValue("--ug-tone-sky-500")).toBe("200 80% 50%");
    expect(style.getPropertyValue("--ug-tone-sky-300")).toBe("200 80% 68%");
    expect(style.getPropertyValue("--ug-tone-sky-600")).toBe("200 80% 42%");
    expect(style.getPropertyValue("--ug-tone-violet-500")).toBe("");
    expect(toneShades("10 50% 90%")[300]).toBe("10 50% 88%");
  });

  it("reads layout and details field by field", () => {
    expect(readLayout(null)).toEqual(DEFAULT_LAYOUT);
    expect(readLayout({ side: "up", slots: "top", hint: "no" })).toEqual({ ...DEFAULT_LAYOUT, slots: "top" });
    expect(readDetails(["born", "born", "nope"])).toEqual(["born"]);
    expect(readDetails(null)).toEqual(["born", "lastPlayed", "location"]);
  });
});

describe("format", () => {
  it("fills placeholders, formats dates and builds initials", () => {
    expect(fill("Slot {index} of {count}", { index: 2, count: 4 })).toBe("Slot 2 of 4");
    expect(fill("{unknown}", {})).toBe("{unknown}");
    expect(formatBirthDate("1995-04-12", "en-US")).toBe("April 12, 1995");
    expect(formatBirthDate("not a date", "en")).toBe("not a date");
    expect(initials("João O'Neil-Costa")).toBe("JO");
  });
});

/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { act, fireEvent, render } from "@testing-library/react";
import { beforeEach, expect, it, vi } from "vitest";
import App from "@/App";
import { DEFAULT_CONFIG, handleMessage, readSpawns, useSceneStore } from "@/store/sceneStore";
import { NuiAction, Screen } from "@/types/protocol";

const nui = vi.hoisted(() => ({
  sendReady: vi.fn(),
  sendCancel: vi.fn(),
  sendSpawnHover: vi.fn(),
  sendSpawnChoose: vi.fn(),
  sendSkip: vi.fn(),
  isEnvBrowser: () => false,
}));

vi.mock("@/lib/nui", () => nui);

const OPTIONS = [
  { id: "last", label: "Last location", street: "Vespucci Boulevard" },
  { id: "legion", label: "Legion Square" },
  { id: "sandy", label: "Sandy Shores" },
];

beforeEach(() => {
  for (const fn of [nui.sendReady, nui.sendCancel, nui.sendSpawnHover, nui.sendSpawnChoose, nui.sendSkip]) {
    fn.mockReset();
  }

  useSceneStore.setState({ config: DEFAULT_CONFIG, screen: null, visible: true, spawns: [], spawnFocus: null });
});

function openPicker() {
  const view = render(<App />);

  act(() => {
    handleMessage({ action: NuiAction.Spawns, payload: { options: OPTIONS, focus: "last" } });
    handleMessage({ action: NuiAction.Screen, payload: { screen: Screen.Spawn } });
  });

  return view;
}

it("rebuilds options from ids and labels only", () => {
  expect(readSpawns([{ id: "a", label: "A", coords: [1, 2, 3] }, { id: "", label: "B" }, "x", { id: "c", label: "C", street: "Route 68" }])).toEqual([
    { id: "a", label: "A" },
    { id: "c", label: "C", street: "Route 68" },
  ]);
});

it("lists the places with the last location's street, and flies over a place on hover", () => {
  const { getByText, getAllByRole } = openPicker();

  expect(getByText("Where to?")).toBeTruthy();
  expect(getByText("Vespucci Boulevard")).toBeTruthy();

  fireEvent.mouseEnter(getAllByRole("option")[2]!);
  expect(nui.sendSpawnHover).toHaveBeenLastCalledWith("sandy");
  expect(useSceneStore.getState().spawnFocus).toBe("sandy");
});

it("moves with the arrows, wraps, chooses with Enter and goes back with Escape", () => {
  openPicker();

  fireEvent.keyDown(window, { key: "ArrowUp" });
  expect(nui.sendSpawnHover).toHaveBeenLastCalledWith("sandy");

  fireEvent.keyDown(window, { key: "ArrowDown" });
  fireEvent.keyDown(window, { key: "ArrowDown" });
  expect(nui.sendSpawnHover).toHaveBeenLastCalledWith("legion");

  fireEvent.keyDown(window, { key: "Enter" });
  expect(nui.sendSpawnChoose).toHaveBeenCalledWith("legion");

  fireEvent.keyDown(window, { key: "Escape" });
  expect(nui.sendCancel).toHaveBeenCalledTimes(1);
});

it("chooses with a click and the button", () => {
  const { getAllByRole, getByRole } = openPicker();

  fireEvent.click(getAllByRole("option")[1]!);
  expect(nui.sendSpawnChoose).toHaveBeenLastCalledWith("legion");

  fireEvent.click(getByRole("button", { name: "Spawn here" }));
  expect(nui.sendSpawnChoose).toHaveBeenLastCalledWith("last");
});

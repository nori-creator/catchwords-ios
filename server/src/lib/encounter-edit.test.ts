import { describe, expect, it } from "vitest";
import { capturePlacePatch, encounterPatch } from "./encounters.functions";

const uid = "11111111-1111-1111-1111-111111111111";
const id = "22222222-2222-2222-2222-222222222222";

describe("encounterPatch (2回目以降の写真を直す)", () => {
  it("a replaced photo drops the old cut-out", () => {
    expect(encounterPatch({ encounter_id: id, image_path: `${uid}/1-encounter.jpg` }, uid)).toEqual({
      image_path: `${uid}/1-encounter.jpg`,
      cutout_path: null,
    });
  });

  it("a new photo sent with its cut-out keeps that cut-out", () => {
    expect(
      encounterPatch(
        { encounter_id: id, image_path: `${uid}/1-encounter.jpg`, cutout_path: `${uid}/1-cutout.png` },
        uid,
      ),
    ).toEqual({ image_path: `${uid}/1-encounter.jpg`, cutout_path: `${uid}/1-cutout.png` });
  });

  it("writes only what was sent (selfie, picture choice, reset to null)", () => {
    expect(encounterPatch({ encounter_id: id, selfie_path: `${uid}/2-selfie.jpg` }, uid)).toEqual({
      selfie_path: `${uid}/2-selfie.jpg`,
    });
    expect(encounterPatch({ encounter_id: id, hero_role: "selfie" }, uid)).toEqual({ hero_role: "selfie" });
    expect(encounterPatch({ encounter_id: id, hero_role: null }, uid)).toEqual({ hero_role: null });
  });

  it("never another person's folder, never an empty edit", () => {
    expect(() => encounterPatch({ encounter_id: id, selfie_path: "someone-else/x.jpg" }, uid)).toThrow();
    expect(() => encounterPatch({ encounter_id: id, cutout_path: "../x.png" }, uid)).toThrow();
    expect(() => encounterPatch({ encounter_id: id }, uid)).toThrow();
  });
});

describe("capturePlacePatch (撮った場所を学習者が直す)", () => {
  it("a point picked on the map: its looked-up name, not a written one", () => {
    expect(
      capturePlacePatch({ sticker_id: id, lat: 25.04, lng: 121.56, location_name: "大安森林公園 大安區", custom: false }),
    ).toEqual({ lat: 25.04, lng: 121.56, location_name: "大安森林公園 大安區", location_custom: false });
  });

  it("a written name is kept as written (trimmed)", () => {
    expect(capturePlacePatch({ encounter_id: id, lat: 25, lng: 121, location_name: "  おばあちゃんの家 ", custom: true })).toEqual({
      lat: 25,
      lng: 121,
      location_name: "おばあちゃんの家",
      location_custom: true,
    });
  });

  it("an empty written name is not a written name (the point's name is looked up again)", () => {
    expect(capturePlacePatch({ sticker_id: id, lat: 25, lng: 121, location_name: "   ", custom: true })).toEqual({
      lat: 25,
      lng: 121,
      location_name: null,
      location_custom: false,
    });
  });
});

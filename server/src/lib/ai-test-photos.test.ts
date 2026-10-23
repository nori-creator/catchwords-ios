import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  AI_TEST_LANGUAGES,
  AI_TEST_PHOTOS,
  AI_TEST_PHOTO_SHA256,
  testPhotoRank,
} from "./ai-test-photos";

const DIR = resolve(__dirname, "../../public/ai-test/photos");

describe("fixed test photos", () => {
  it("lists every photo in public/ai-test/photos once, with answers in every learning language", () => {
    const files = readdirSync(DIR)
      .filter((f) => f.endsWith(".jpg"))
      .map((f) => f.slice(0, -4))
      .sort();
    expect(AI_TEST_PHOTOS.map((p) => p.id).sort()).toEqual(files);
    for (const p of AI_TEST_PHOTOS)
      for (const lang of AI_TEST_LANGUAGES) expect(p.labels[lang].length).toBeGreaterThan(0);
  });

  it("knows each photo's digest (the server checks the image it is sent against it)", () => {
    for (const p of AI_TEST_PHOTOS) {
      const sha = createHash("sha256")
        .update(readFileSync(resolve(DIR, `${p.id}.jpg`)))
        .digest("hex");
      expect(AI_TEST_PHOTO_SHA256[p.id], p.id).toBe(sha);
    }
  });

  it("ranks the first accepted headword (spaces and case ignored)", () => {
    expect(testPhotoRank(["杯子", "珍珠 奶茶"], ["珍珠奶茶"])).toBe(2);
    expect(testPhotoRank(["Coffee"], ["coffee"])).toBe(1);
    expect(testPhotoRank(["杯子"], ["珍珠奶茶"])).toBeNull();
  });
});

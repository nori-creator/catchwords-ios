import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: [
      { find: /^@tanstack\/react-start\/server$/, replacement: path.resolve(__dirname, "shims/tanstack-start-server.ts") },
      { find: /^@tanstack\/react-start$/, replacement: path.resolve(__dirname, "shims/tanstack-start.ts") },
      { find: /^@\//, replacement: path.resolve(__dirname, "src") + "/" },
    ],
  },
});

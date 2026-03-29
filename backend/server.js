import dotenv from "dotenv";
import { getServerConfig } from "./src/config/env.js";
import { createApp } from "./src/app.js";

dotenv.config();

const { port } = getServerConfig();
const app = createApp();

process.on("unhandledRejection", (reason) => {
  console.error("[backend] unhandledRejection", reason);
});

process.on("uncaughtException", (error) => {
  console.error("[backend] uncaughtException", error);
  process.exit(1);
});

app.listen(port, () => {
  console.log(`[backend] listening on http://0.0.0.0:${port}`);
});

import cors from "cors";
import express from "express";
import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";
import aiRouter from "./routes/ai.js";
import healthRouter from "./routes/health.js";

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: "10mb" }));
  app.use((req, _res, next) => {
    console.log(`[backend] ${req.method} ${req.originalUrl}`);
    next();
  });

  app.get("/", (_req, res) => {
    res.json({
      service: "cuotiben-backend",
      message: "Backend service is running."
    });
  });

  app.use("/health", healthRouter);
  app.use("/ai", aiRouter);
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

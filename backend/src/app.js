import cors from "cors";
import express from "express";
import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";
import aiRouter from "./routes/ai.js";
import healthRouter from "./routes/health.js";

function createInitialAIGatewayStatus() {
  return {
    circuitState: "closed",
    lastErrorCode: null,
    lastRequestId: null,
    updatedAt: null
  };
}

function recordAIGatewayObservation(app, payload) {
  const status = app.locals.aiGatewayStatus || createInitialAIGatewayStatus();
  const nextState = {
    ...status,
    updatedAt: new Date().toISOString()
  };

  if (typeof payload?.request_id === "string" && payload.request_id.trim()) {
    nextState.lastRequestId = payload.request_id.trim();
  }

  if (typeof payload?.error_code === "string" && payload.error_code.trim()) {
    nextState.lastErrorCode = payload.error_code.trim();
  } else if (payload?.success === true) {
    nextState.lastErrorCode = null;
  }

  if (typeof payload?.meta?.circuit_state === "string" && payload.meta.circuit_state.trim()) {
    nextState.circuitState = payload.meta.circuit_state.trim();
  } else if (payload?.error_code === "MODEL_CONFIG_MISSING") {
    nextState.circuitState = "closed";
  }

  app.locals.aiGatewayStatus = nextState;
}

export function createApp() {
  const app = express();
  app.locals.aiGatewayStatus = createInitialAIGatewayStatus();

  app.use(cors());
  app.use(express.json({ limit: "10mb" }));
  app.use((req, _res, next) => {
    console.log(`[backend] ${req.method} ${req.originalUrl}`);
    next();
  });
  app.use((req, res, next) => {
    if (!req.originalUrl.startsWith("/ai")) {
      return next();
    }

    const originalJson = res.json.bind(res);
    res.json = (body) => {
      recordAIGatewayObservation(app, body);
      return originalJson(body);
    };
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

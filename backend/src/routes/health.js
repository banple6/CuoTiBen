import { Router } from "express";

const router = Router();

router.get("/", (_req, res) => {
  res.json({
    ok: true,
    service: "cuotiben-backend",
    timestamp: new Date().toISOString(),
    node: process.version
  });
});

export default router;

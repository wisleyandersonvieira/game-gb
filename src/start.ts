import { createStart } from "@tanstack/react-start";
import { getRouter } from "./router";

export const startInstance = createStart(() => ({
  router: getRouter(),
}));

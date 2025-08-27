import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("WasopayModule", (m) => {
  // First deploy AccessControl contract
  const accessControl = m.contract("AccessControl");

  // Then deploy WasoPay with AccessControl address
  const wasopay = m.contract("WasoPay", [accessControl]);

  return { accessControl, wasopay };
});

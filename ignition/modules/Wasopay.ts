import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("WasopayModule", (m) => {
  const wasopay = m.contract("Wasopay");

  // m.call(counter, "incBy", [5n]);

  return { wasopay };
});

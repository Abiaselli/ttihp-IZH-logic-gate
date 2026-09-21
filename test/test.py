# SPDX-License-Identifier: Apache-2.0
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

def bit(signal, index):
    return (int(signal.value) >> index) & 1

async def wait_bit(signal, index, value, clk, limit=10000):
    for _ in range(limit):
        if bit(signal, index) == value:
            return
        await RisingEdge(clk)
    raise AssertionError(f"timeout waiting for bit {index}={value}")

async def transact(dut, command):
    assert len(command) == 5

    # Command channel: uio[0]=valid, uio[1]=ready.
    for byte in command:
        await wait_bit(dut.uio_out, 1, 1, dut.clk)
        dut.ui_in.value = byte
        dut.uio_in.value = 0x01
        await RisingEdge(dut.clk)
        dut.uio_in.value = 0x00
        await RisingEdge(dut.clk)

    # Response channel: uio[3]=valid, uio[2]=ready.
    await wait_bit(dut.uio_out, 3, 1, dut.clk)
    response = []
    for _ in range(5):
        await Timer(1, unit="ns")
        response.append(int(dut.uo_out.value))
        dut.uio_in.value = 0x04
        await RisingEdge(dut.clk)
        dut.uio_in.value = 0x00
        await RisingEdge(dut.clk)

    return response

@cocotb.test()
async def test_bridge_protocol(dut):
    # Nominal 20 MHz project clock.
    cocotb.start_soon(Clock(dut.clk, 50, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 6)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # uio[1] and uio[3] are ASIC outputs; all other uio pins are inputs.
    assert int(dut.uio_oe.value) == 0x0A

    # Read neuron 0 membrane voltage after reset.
    # Default encoded V=-65 is signed 18-bit 0x3599A.
    response = await transact(dut, [0x02, 0x00, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x00, 0x9A, 0x59, 0x03]

    # Write bias/current = +10 model units => encoded 6554 = 0x199A.
    response = await transact(dut, [0x01, 0x30, 0x9A, 0x19, 0x00])
    assert response == [0x00, 0x30, 0x00, 0x00, 0x00]

    # Read it back.
    response = await transact(dut, [0x02, 0x30, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x30, 0x9A, 0x19, 0x00]

    # Advance one full network step. From reset with only neuron 0 biased at 10,
    # no neuron should spike on the first step.
    response = await transact(dut, [0x03, 0x00, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x00, 0x00, 0x00, 0x00]

    # Confirm neuron 0 voltage advanced from -65.
    response = await transact(dut, [0x02, 0x00, 0x00, 0x00, 0x00])
    # Reference integer model gives -42311 => signed 18-bit 0x35AB9.
    assert response == [0x00, 0x00, 0xB9, 0x5A, 0x03]

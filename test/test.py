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
    # Nominal 10 MHz project clock.
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 6)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    assert int(dut.uio_oe.value) == 0x0A

    response = await transact(dut, [0x02, 0x00, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x00, 0x9A, 0x59, 0x03]

    response = await transact(dut, [0x01, 0x30, 0x9A, 0x19, 0x00])
    assert response == [0x00, 0x30, 0x00, 0x00, 0x00]

    response = await transact(dut, [0x02, 0x30, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x30, 0x9A, 0x19, 0x00]

    response = await transact(dut, [0x03, 0x00, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x00, 0x00, 0x00, 0x00]

    response = await transact(dut, [0x02, 0x00, 0x00, 0x00, 0x00])
    assert response == [0x00, 0x00, 0xB9, 0x5A, 0x03]

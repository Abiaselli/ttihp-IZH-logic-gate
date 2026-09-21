## How it works

This project implements 16 independently stored fixed-point Izhikevich neuron contexts in a `6x4` Tiny Tapeout IHP slot. A single signed serial multiplier and control engine are time-multiplexed across all contexts to reduce duplicated arithmetic.

Each neuron stores membrane voltage V, recovery state U, synaptic current, bias/current, parameters a/b/c/d, two signed synaptic weights, and two source identifiers. Source IDs can select prior-step recurrent spikes or one of four external digital spike inputs. A STEP command advances every neuron once and returns the resulting spike bitmap.

The four external event inputs are digital logic signals. Analog neurons must currently be connected through external comparators/Schmitt receivers/level conditioning. This digital build does not contain an ADC, DAC, or on-chip analog comparator.

## How to test

Use the supplied cocotb test:

```sh
cd test
pip install -r requirements.txt
make -B
```

The test resets the design, checks bidirectional pin direction, reads the reset membrane voltage, writes and reads back a bias/current value, advances one full network step, and verifies the resulting state against the integer reference model.

For full numerical regression, the original prototype's Verilator/vector tests are retained in `prototype_docs/`.

## External hardware

Intended system:
- FPGA providing clock, packet transport, buffering, and larger network routing.
- Up to four external comparator/level-conditioned spike sources.
- Optional external DAC/current-pulse drivers controlled by the FPGA for feedback into analog neurons.

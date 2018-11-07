# dualVth - Group 8
This project has been conceived during the "Synthesis and Optimization of Embedded Systems" course held by Prof. Calimera, Politecnico di Torino (AY 2017/18).

## Goal
The aim of this tcl script is to write a plug-in for PrimeTime in to obtain a post synthesis power minimization.
The new command tries to reassign LVT cells with HVT such that the slack penalties are minimized while still reaching the desitred power savings. Another rele
vant parameter taken into account is the CPU time needed to complete the optim
ization required, which has been sensibly minimized.

## Example
After having synthesized the circuit with dc\_shell, and started PrimeTime, one should simply launch the script:
```
source dualVth.tcl
```
Then, you just need to launch the included procedure, adding the required arguments:
```
dualVth -leakage $savings$
```
The parameter savings is given as a normalized value, i.e. it ranges from [0,1].

## Contacts
For any information, you can simply drop an email:
* [Alberto Anselmo](mailto:s251291@studenti.polito.it)
* [Riccardo Cappai](mailto:s251646@studenti.polito.it)
* [Giulio Roggero](mailto:s251311@studenti.polito.it)	

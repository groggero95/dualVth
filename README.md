# dualVth
The aim is to write a plug-in for PrimeTime in tcl to obtain a post synthesis power minimization.

The new command tries to reassign LVT cells with HVT such that the slack penalties are minimized while still reaching the desitred power savings.

## Example
```
dualVth -leakage $savings$
```
The parameter savings is given as a pescentage value, i.e. it ranges from [0,1].

# [SigScale](http://www.sigscale.org) Custom/CAMEL Service Environment (CSE)

This application provides a Service Logic Execution Environment (SLEE)
for Service Logic Processing Programs (SLP) implementing a network
operator's custom services. Several protocol stacks are supported
including CAP, INAP, DIAMETER, RADIUS and REST.

Provided SLPs support real-time charging for prepaid services with
CAP (CAMEL), INAP and DIAMETER interfaces. These SLPs implement the
Online Charging Function (OCF) of a decomposed OCS (Online Charging
System) (3GPP TS 32.296) using the
[NRF_Rating](https://app.swaggerhub.com/apis/SigScale/nrf-rating/1.0.0)
API on the Re interface to a remote Rating Function (RF) such as
SigScale OCS.
 
![screenshot](https://raw.githubusercontent.com/sigscale/cse/master/doc/ocf-ocs.svg)


# IndustrialFlow Architecture

IndustrialFlow is built around four independent systems.

## Simulation

Responsible for all machine behaviour.

## Editor

Responsible for graph editing.

## User Interface

Responsible only for presentation.

## Content

Provides machines, recipes and research.

These systems communicate through clearly defined interfaces and should remain
loosely coupled wherever practical.
---
title: Architecture
description: High-level architecture, data flow, and design choices for HealthPush.
---

This document describes the high-level architecture of HealthPush.

## Overview

HealthPush follows a clean, layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │  Presentation
├─────────────────────────────────────────┤
│              App State                  │  State Management
├─────────────────────────────────────────┤
│  HealthKit Service  │  Sync Engine      │  Business Logic
├─────────────────────────────────────────┤
│         Destination Protocol            │  Abstraction Layer
├──────────┬──────────┬───────────────────┤
│ Home     │  CSV     │  Future           │  Concrete
│ Assistant│  Export  │  Destinations     │  Implementations
└──────────┴──────────┴───────────────────┘
```

## Core Components

### App Layer (`Sources/App/`)

- **`HealthPushApp`** -- SwiftUI app entry point. Registers background tasks and sets up the environment.
- **`AppState`** -- Observable state container shared across views. Holds sync status, destination list, and configuration.

### Models (`Sources/Models/`)

- **`HealthDataPoint`** -- The universal data structure for a single health measurement. Contains the metric type, value, unit, and timestamp.
- **`HealthMetricType`** -- Enum of all supported Apple Health metrics (steps, heart rate, blood oxygen, etc.). Maps to `HKQuantityTypeIdentifier` and `HKCategoryTypeIdentifier`.
- **`SyncFrequency`** -- Enum representing how often background syncs run.
- **`SyncRecord`** -- Persisted record of each sync attempt (timestamp, destination, success/failure, data point count).
- **`DestinationConfig`** -- SwiftData model for persisting destination settings.

### Views (`Sources/Views/`)

- **`Screens/`** -- Full-screen views: Dashboard, Destinations list, Health Metrics picker, Settings, and per-destination setup screens.
- **`Components/`** -- Reusable UI elements shared across screens.

All views use SwiftUI and target iOS 17+. Views observe `AppState` for reactive updates.

### Services (`Sources/Services/`)

- **HealthKit Service** -- Wraps `HKHealthStore`. Handles authorization, queries, and observer queries for real-time updates.
- **Background Sync Service** -- Manages `BGTaskScheduler` registration and execution. Coordinates the sync cycle: query HealthKit, batch data, dispatch to destinations.
- **Network Service** -- Thin wrapper around `URLSession` for making HTTP requests. Used by destinations that push over the network.

### Destinations (`Sources/Destinations/`)

- **`SyncDestination`** -- The core protocol. Every sync target implements this.
- **`DestinationManager`** -- Registry of available destination types. Handles creating, storing, and retrieving configured destinations.
- **`HomeAssistantDestination`** -- The primary destination. Pushes health data to a Home Assistant instance via webhook.

## Data Flow

### Manual Sync

```
User taps "Sync Now"
  → AppState triggers sync
    → HealthKit Service queries recent data
      → Returns [HealthDataPoint]
        → For each enabled destination:
          → destination.sync(data:) called
            → HTTP POST to destination
              → SyncRecord saved
                → UI updates via AppState
```

### Background Sync

```
BGTaskScheduler fires
  → Background Sync Service wakes
    → Same flow as manual sync
      → Schedules next background task
```

## Persistence

- **SwiftData** stores all local state:
  - Destination configurations (URLs, tokens, enabled metrics)
  - Sync history (SyncRecord)
  - User preferences (sync frequency, selected metrics)
- **No iCloud sync** -- everything stays on-device
- **Keychain-backed secrets** -- destination credentials are stored in Keychain; SwiftData stores only non-secret configuration and sync metadata

## Home Assistant Integration

The HA side is a custom component (`integrations/homeassistant/custom_components/healthpush/`):

```
HealthPush iOS App
  → HTTPS POST /api/webhook/<webhook_id>
    → HA custom component receives data
      → Creates/updates sensor entities
        → sensor.healthpush_steps, sensor.healthpush_heart_rate, etc.
```

The component:
- Registers a webhook during config flow setup
- Parses incoming health data payloads
- Registers sensor entities with proper device classes, units, and icons, then updates them as webhook data arrives
- Supports multiple iOS devices reporting to the same HA instance

## Design Decisions

### Why no third-party dependencies?

Trust and auditability. Users are sending health data through this app. Every line of code should be inspectable in this repo. No transitive dependency surprises.

### Why BGTaskScheduler instead of push notifications?

Push notifications would require a server. BGTaskScheduler keeps the architecture fully local -- no intermediary, no accounts, no server to maintain.

### Why SwiftData over Core Data?

SwiftData is the modern replacement, integrates natively with SwiftUI, and reduces boilerplate. Since we target iOS 17+, there is no compatibility concern.

### Why webhooks instead of the HA REST API?

Webhooks are the standard pattern for external integrations pushing data into Home Assistant. They are simpler, require less auth surface, and work with the existing HA infrastructure.

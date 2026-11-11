# Honeybee Center — Migration Guide

A practical, beginner-friendly guide to the Honeybee Center backend migration from Firebase to Supabase.

---

## 1. System Architecture Overview

Honeybee Center operates on a dual-backend architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                   Honeybee Center App                       │
│              (Flutter Web & Mobile Clients)                 │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
    ┌────────────────────┐         ┌────────────────────┐
    │  Supabase Backend  │         │  Firebase Realtime │
    │   (Primary Data)   │         │  Database (IoT)    │
    └──────────┬─────────┘         └──────────┬─────────┘
               │                              │
       ┌───────┴───────┐                      ▼
       │               │             ┌─────────────────┐
       ▼               ▼             │    ESP32-CAM    │
  PostgreSQL      Supabase Auth      │  (Bottle Scans) │
  (19 Tables)     (JWT & RLS)        └─────────────────┘
```

1. **Supabase (`gvteqrtvpfujfrwrdohv`):**
   * Manages authentication, products, stock pools, orders, production, customers, and reports.
   * PostgreSQL enforces Row-Level Security (RLS) and atomic stock transactions.
2. **Firebase Realtime Database:**
   * Retained exclusively for ESP32-CAM communication (`/scan_commands` and `/scan_results`).
   * Camera bottle detection (250g, 500g, 1kg) is **verification-only** and never mutates inventory directly.

---

## 2. Project Setup & Configuration

* **Supabase URL:** `https://gvteqrtvpfujfrwrdohv.supabase.co`
* **Project Reference:** `gvteqrtvpfujfrwrdohv`
* **Region:** `ap-northeast-2` (Seoul, South Korea)
* **Configuration File:** `lib/config/supabase_config.dart`

To run the Flutter app locally with the Supabase client:
```bash
flutter run -d chrome
```

---

## 3. Database Tables & Key Relationships

The 19 verified tables in `public` schema include:
* **`admins`:** Administrative users (`main_admin`, `co_admin`). Primary key references `auth.users(id)`.
* **`products` & `product_variants`:** Honey products and size variants (250g, 500g, 1kg).
* **`inventory` & `inventory_movements`:** Warehouse bulk stock and auditable movement logs.
* **`orders` & `order_items`:** Customer orders and line items.
* **`production_batches` & `production_batch_items`:** Honey production batch tracking.
* **`customers`:** Customer accounts linked to `auth.users`.
* **`otp_sessions` & `password_reset_sessions`:** Tables supporting custom OTP password recovery.

---

## 4. Role Hierarchy & Access Rules

1. **Main Admin (`role: 'main_admin'`, `reylbanocnoc@gmail.com`):**
   * Full access to financial reports, owner panel, system settings, and administrator account management.
2. **Co-Admin (`role: 'co_admin'`, `coadmin67@gmail.com`):**
   * Daily operations: order fulfillment, inventory replenishment, batch updates, customer pickup QR scanning.
   * Strictly blocked from deleting administrative accounts or modifying system permissions.

---

## 5. ESP32-CAM IoT Coexistence Rules

* The ESP32-CAM firmware communicates with Firebase Realtime Database.
* When a scan is requested:
  1. The Flutter app posts `{ "command": "scan", "timestamp": ... }` to Firebase `/scan_commands`.
  2. The ESP32-CAM captures the image, classifies bottle sizes (250g, 500g, 1kg), and posts counts to `/scan_results`.
  3. The Flutter app displays the comparison between physical counts and system inventory.
  4. Any discrepancy requires authorized human confirmation before an inventory adjustment is created in Supabase.

---

## 6. Backup, Recovery & Rollback Protocols

1. **Source Data Safety:** Firebase Realtime Database nodes are kept intact throughout the migration.
2. **Database Rollback:** Supabase migrations are versioned under `supabase/migrations/`.
3. **Emergency Fallback:** The Flutter application retains existing Firebase dependencies in `pubspec.yaml` until all modules are verified in Supabase.

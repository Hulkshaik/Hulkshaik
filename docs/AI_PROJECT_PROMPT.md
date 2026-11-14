# FINAL ARCHITECTURE UPDATE – MY TOWN TAXI

IMPORTANT: Build ONLY TWO APPLICATION SYSTEMS:

1. ONE unified Android application for both car owners and car renters.
2. ONE web-based Admin Dashboard.

Do not create a separate owner application or driver application.

## Unified Android App

Use one account with two operating modes:

- **Rent a Car**: Search, compare, book and rent self-drive vehicles.
- **List Your Car**: Register vehicles, manage listings, accept bookings and view earnings.

Users can switch between both modes without creating separate accounts.

Main navigation: Home, Explore Cars, My Bookings, My Vehicles, Profile.

## Mandatory Before-and-After Vehicle Photo Gallery

Every rental booking must have two inspection galleries.

**BEFORE PICKUP**
- Front, rear, left and right vehicle photographs.
- Interior and seat photographs.
- Dashboard and odometer.
- Fuel or battery level.
- Existing scratches, dents and damage.
- Tyres and accessories.

**AFTER RETURN**
- Repeat all inspection photographs.
- Record final odometer.
- Record fuel or battery level.
- Document new scratches or damage.
- Compare vehicle condition with initial photographs.

### Gallery Requirements

- Display before and after images side by side.
- Include individual image comparison.
- Allow image enlargement.
- Group photographs by vehicle and booking.
- Store timestamps and uploader identity.
- Preserve original photographs (never overwrite or edit originals).
- Support secure image storage.
- Require owner and renter inspection acknowledgements.
- Allow either party to report discrepancies.
- Maintain inspection history.
- Never automatically declare damage solely using AI image comparison.
- Every photo carries: booking ID, timestamp, uploader identity, inspection stage.

### Workflow Gates

- A booking cannot be marked handed over until the BEFORE inspection is completed.
- The return workflow cannot be closed until the AFTER inspection is recorded
  or an authorized exception is documented.

## Admin Dashboard Gallery Management

Create a dedicated Vehicle Inspection and Gallery module.

Admin must be able to:
- View every booking's before gallery.
- View every booking's after gallery.
- Compare photographs.
- Review odometer and fuel readings.
- View owner and renter confirmations.
- Review damage claims.
- Resolve disputes.
- Export inspection records where permitted.

Admin modules: Owners, Customers, Vehicles, Bookings, Before gallery,
After gallery, Comparison, Payments, Disputes, Commission, Reports.

## Database

Add: `inspection_records`, `inspection_photos`, `inspection_acknowledgements`,
`damage_reports`, `dispute_records`.

Link every inspection to the correct booking, vehicle, owner and renter.

This architecture is mandatory throughout the entire project.
Do not create extra Android applications.

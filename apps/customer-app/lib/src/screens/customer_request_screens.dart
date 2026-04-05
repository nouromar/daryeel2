import 'package:flutter/material.dart';
import 'package:flutter_daryeel_client_app/flutter_daryeel_client_app.dart';

class CustomerRequestRoutes {
  static const ambulance = 'customer.request.ambulance';
  static const homeVisit = 'customer.request.home_visit';
  static const pharmacy = 'customer.request.pharmacy';
}

class CustomerPharmacyRoutes {
  static const prescriptionUpload = 'customer.pharmacy.prescription_upload';
}

class CustomerServiceRoutes {
  static const detail = 'customer.service.detail';
}

class CustomerRequestScreenIds {
  static const ambulance = 'customer_request_ambulance';
  static const homeVisit = 'customer_request_home_visit';
  static const pharmacy = 'pharmacy_shop';
}

class CustomerPharmacyScreenIds {
  static const prescriptionUpload = 'pharmacy_prescription_upload';
}

class CustomerServiceScreenIds {
  static const detail = 'customer_service_detail';
}

Map<String, WidgetBuilder> buildCustomerAdditionalRoutes() {
  return <String, WidgetBuilder>{
    CustomerRequestRoutes.ambulance: (context) => SchemaRoutedScreen(
      screenId: CustomerRequestScreenIds.ambulance,
      title: 'Ambulance',
    ),
    CustomerRequestRoutes.homeVisit: (context) => SchemaRoutedScreen(
      screenId: CustomerRequestScreenIds.homeVisit,
      title: 'Home Visit',
    ),
    CustomerRequestRoutes.pharmacy: (context) => SchemaRoutedScreen(
      screenId: CustomerRequestScreenIds.pharmacy,
      title: 'Pharmacy',
    ),
    CustomerPharmacyRoutes.prescriptionUpload: (context) =>
        const SchemaRoutedScreen(
          screenId: CustomerPharmacyScreenIds.prescriptionUpload,
          title: 'Attach Prescription',
        ),
    CustomerServiceRoutes.detail: (context) => const SchemaRoutedScreen(
      screenId: CustomerServiceScreenIds.detail,
      title: 'Service',
    ),
  };
}

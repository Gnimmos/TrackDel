// src/screens/PendingDeliveriesScreen.tsx
import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Linking,
  Alert,
} from 'react-native';
import MapView, { Marker, LatLng } from 'react-native-maps';
import { StackNavigationProp } from '@react-navigation/stack';
import { RootStackParamList } from '../AppNavigator';

// Dummy data for a delivery
const delivery = {
  orderNumber: 104,
  totalOrders: '1/2',
  customer: 'MARIOS AVRAAM',
  phone: '99678762',
  address: 'LEOFOROS ARCHIEBISKOPU\nMAKARIOU III, STROVOLOS 1096',
  orderId: 'IRL 2025/125',
  amount: '45,20',
  paid: false,
  orderTime: '13:10',
  dispatchTime: '13:25',
  promisedTime: '13:40',
  eta: '13:38',
  coordinates: {
    latitude: 37.78825,
    longitude: -122.4324,
  },
};

const driverLocation: LatLng = {
  latitude: 37.7875,
  longitude: -122.435,
};

const getCenterCoordinate = (coord1: LatLng, coord2: LatLng) => {
  return {
    latitude: (coord1.latitude + coord2.latitude) / 2,
    longitude: (coord1.longitude + coord2.longitude) / 2,
  };
};

const getLatLngDelta = (coord1: LatLng, coord2: LatLng) => {
  const baseLatDelta = Math.abs(coord1.latitude - coord2.latitude);
  const baseLngDelta = Math.abs(coord1.longitude - coord2.longitude);

  return {
    latitudeDelta: Math.max(baseLatDelta, 0.0008),
    longitudeDelta: Math.max(baseLngDelta, 0.0008),
  };
};

type Props = {
  navigation: StackNavigationProp<RootStackParamList, 'PendingDeliveries'>;
};

const PendingDeliveriesScreen: React.FC<Props> = ({ navigation }) => {
  const handleCall = () => Linking.openURL(`tel:${delivery.phone}`);
  const handleMap = () => navigation.navigate('Map');
  const handleAmountPress = () =>
    Alert.alert('Order Details', '1x Pizza\n1x Soda\nTotal: €45.20');

  const region = {
    ...getCenterCoordinate(delivery.coordinates, driverLocation),
    ...getLatLngDelta(delivery.coordinates, driverLocation),
  };

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.headerRow}>
        <Text style={styles.dateText}>FRI 16th MAY</Text>
        <Text style={styles.timeText}>11:39:25</Text>
      </View>

      <View style={styles.deliveryBlock}>
        <View style={styles.logoRow}>
          <View style={styles.logoPlaceholder} />
          <View style={styles.orderInfo}>
            <Text style={styles.orderNumber}>ORDER NO: {delivery.orderNumber}</Text>
            <Text style={styles.orderCount}>{delivery.totalOrders}</Text>
          </View>
        </View>

        <Text style={styles.customer}>{delivery.customer}</Text>

        <TouchableOpacity onPress={handleCall}>
          <Text style={styles.phone}>{delivery.phone}</Text>
        </TouchableOpacity>

        <Text style={styles.address}>{delivery.address}</Text>

        <View style={styles.rowBetween}>
          <Text style={styles.meta}>{delivery.orderId}</Text>
          <TouchableOpacity onPress={handleAmountPress}>
            <Text style={styles.amount}>€{delivery.amount}</Text>
          </TouchableOpacity>
          <Text style={[styles.status, { color: delivery.paid ? 'green' : 'red' }]}>  
            {delivery.paid ? 'PAID' : 'UNPAID'}
          </Text>
        </View>

        <View style={styles.etaBox}>
          <Text>Order Time: {delivery.orderTime}</Text>
          <Text>Despatch Time: {delivery.dispatchTime}</Text>
          <Text>Promised Time: {delivery.promisedTime}</Text>
          <Text style={styles.etaText}>E.T.A {delivery.eta}</Text>
        </View>

        <TouchableOpacity onPress={handleMap} activeOpacity={0.9}>
          <MapView
            style={styles.miniMap}
            initialRegion={region}
            scrollEnabled={false}
            zoomEnabled={false}
            pitchEnabled={false}
            rotateEnabled={false}
            pointerEvents="none"
          >
            <Marker coordinate={delivery.coordinates} title="Delivery" />
            <Marker coordinate={driverLocation} pinColor="blue" title="You" />
          </MapView>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.deliveredBtn}
          onPress={() => {
            if (delivery.paid) {
              Alert.alert('Delivered', 'Proceed to next order.');
            } else {
              Alert.alert('Payment Pending', 'Cash or Visa?', [
                { text: 'Cash', onPress: () => {} },
                { text: 'Visa', onPress: () => {} },
              ]);
            }
          }}
        >
          <Text style={styles.btnText}>DELIVERED</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
};

export default PendingDeliveriesScreen;

const styles = StyleSheet.create({
  container: { padding: 20 },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 10,
  },
  dateText: { fontSize: 16, fontWeight: 'bold' },
  timeText: { fontSize: 16, fontWeight: 'bold' },
  deliveryBlock: {
    borderWidth: 1,
    padding: 15,
    borderRadius: 10,
    backgroundColor: '#fff',
  },
  logoRow: { flexDirection: 'row', alignItems: 'center' },
  logoPlaceholder: {
    width: 40,
    height: 40,
    backgroundColor: '#ddd',
    borderRadius: 20,
    marginRight: 10,
  },
  orderInfo: { flexDirection: 'row', justifyContent: 'space-between', flex: 1 },
  orderNumber: { fontSize: 16, fontWeight: 'bold' },
  orderCount: { fontSize: 16, fontWeight: 'bold', color: 'orange' },
  customer: { fontSize: 18, fontWeight: 'bold', marginTop: 10 },
  phone: { color: 'blue', marginVertical: 5 },
  address: { fontSize: 14, marginBottom: 10 },
  rowBetween: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  meta: { fontSize: 14 },
  amount: { color: 'blue', fontWeight: 'bold' },
  status: { fontWeight: 'bold' },
  etaBox: {
    marginVertical: 15,
    borderWidth: 1,
    padding: 10,
    borderRadius: 5,
  },
  etaText: { fontSize: 24, fontWeight: 'bold', textAlign: 'right' },
  miniMap: {
    height: 150,
    borderRadius: 10,
    marginVertical: 10,
    overflow: 'hidden',
  },
  deliveredBtn: {
    backgroundColor: 'black',
    padding: 15,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 10,
  },
  btnText: { color: 'white', fontWeight: 'bold' },
});

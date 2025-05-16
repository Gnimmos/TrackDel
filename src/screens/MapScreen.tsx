// src/screens/MapScreen.tsx
import React, { useEffect, useRef, useState } from 'react';
import { View, StyleSheet, Button, Alert } from 'react-native';
import MapView, { Marker, Polyline, LatLng } from 'react-native-maps';
import { StackNavigationProp } from '@react-navigation/stack';
import { RootStackParamList } from '../AppNavigator';
import axios from 'axios';
import { GOOGLE_MAPS_API_KEY } from '@env';

type Props = {
  navigation: StackNavigationProp<RootStackParamList, 'Map'>;
};

const MapScreen: React.FC<Props> = ({ navigation }) => {
  const mapRef = useRef<MapView>(null);
  const [routeCoords, setRouteCoords] = useState<LatLng[]>([]);

  const deliveryLocation: LatLng = { latitude: 37.78825, longitude: -122.4324 };
  const driverLocation: LatLng = { latitude: 37.7875, longitude: -122.435 };

  useEffect(() => {
    fetchRoute(driverLocation, deliveryLocation);
  }, []);

  const handleMapReady = () => {
    if (mapRef.current) {
      mapRef.current.fitToCoordinates([driverLocation, deliveryLocation], {
        edgePadding: { top: 40, right: 40, bottom: 40, left: 40 },
        animated: true,
      });
    }
  };

  const fetchRoute = async (origin: LatLng, destination: LatLng) => {
    const originStr = `${origin.latitude},${origin.longitude}`;
    const destStr = `${destination.latitude},${destination.longitude}`;

    try {
      const response = await axios.get(
        `https://maps.googleapis.com/maps/api/directions/json?origin=${originStr}&destination=${destStr}&key=${GOOGLE_MAPS_API_KEY}`
      );

      if (response.data.routes.length) {
        const points = decodePolyline(
          response.data.routes[0].overview_polyline.points
        );
        setRouteCoords(points);
      }
    } catch (err) {
      console.error('Error fetching route', err);
      Alert.alert('Map error', 'Could not load route');
    }
  };

  const decodePolyline = (t: string): LatLng[] => {
    let points: LatLng[] = [];
    let index = 0,
      lat = 0,
      lng = 0;

    while (index < t.length) {
      let b,
        shift = 0,
        result = 0;
      do {
        b = t.charCodeAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      let dlat = result & 1 ? ~(result >> 1) : result >> 1;
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = t.charCodeAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      let dlng = result & 1 ? ~(result >> 1) : result >> 1;
      lng += dlng;

      points.push({ latitude: lat / 1e5, longitude: lng / 1e5 });
    }

    return points;
  };

  const handleDeliveredPress = () => {
    navigation.navigate('PendingDeliveries');
  };

  return (
    <View style={styles.container}>
      <MapView
        ref={mapRef}
        style={styles.map}
        onMapReady={handleMapReady}
      >
        <Marker coordinate={deliveryLocation} title="Delivery" />
        <Marker coordinate={driverLocation} title="You" pinColor="blue" />
        {routeCoords.length > 0 && (
          <Polyline coordinates={routeCoords} strokeColor="blue" strokeWidth={4} />
        )}
      </MapView>

      <View style={styles.buttonContainer}>
        <Button title="Delivered" onPress={handleDeliveredPress} />
      </View>
    </View>
  );
};

export default MapScreen;

const styles = StyleSheet.create({
  container: { flex: 1 },
  map: {
    ...StyleSheet.absoluteFillObject,
  },
  buttonContainer: {
    position: 'absolute',
    bottom: 30,
    left: 20,
    right: 20,
  },
});

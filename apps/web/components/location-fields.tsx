'use client';
import { useState } from 'react';

/** Lat/lng/accuracy inputs with a "use my location" button (browser geolocation, high accuracy). */
export function LocationFields() {
  const [coords, setCoords] = useState({ lat: '', lng: '', accuracy: '' });
  const [status, setStatus] = useState<string>('');

  function locate() {
    if (!('geolocation' in navigator)) {
      setStatus('This browser cannot share location. Enter the coordinates manually.');
      return;
    }
    setStatus('Locating…');
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setCoords({
          lat: pos.coords.latitude.toFixed(6),
          lng: pos.coords.longitude.toFixed(6),
          accuracy: String(Math.round(pos.coords.accuracy)),
        });
        setStatus(`Location captured (±${Math.round(pos.coords.accuracy)} m).`);
      },
      (err) => setStatus(`Could not get location: ${err.message}`),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  }

  return (
    <fieldset className="stack" style={{ border: 0, padding: 0, margin: 0 }}>
      <button type="button" className="secondary" onClick={locate}>Use my current location</button>
      {status ? <span className="muted" role="status">{status}</span> : null}
      <label>Latitude<input name="lat" inputMode="decimal" required value={coords.lat}
        onChange={(e) => setCoords({ ...coords, lat: e.target.value })} /></label>
      <label>Longitude<input name="lng" inputMode="decimal" required value={coords.lng}
        onChange={(e) => setCoords({ ...coords, lng: e.target.value })} /></label>
      <label>GPS accuracy (metres)<input name="accuracy" inputMode="numeric" required value={coords.accuracy}
        onChange={(e) => setCoords({ ...coords, accuracy: e.target.value })} /></label>
    </fieldset>
  );
}

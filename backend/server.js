const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');

const app = express();
const PORT = 3000;

app.use(cors());
app.use(bodyParser.json());

// Mock Data
const drivers = [
    { name: "John Doe", vehicle: "Toyota Prius", plate: "AB12 CDE", rating: 4.8 },
    { name: "Sarah Smith", vehicle: "Tesla Model 3", plate: "XY98 ZYW", rating: 4.9 },
    { name: "Michael Brown", vehicle: "Ford Mondeo", plate: "LM45 NOP", rating: 4.7 }
];

let currentRideStatus = "driver_assigned";

// Routes

// 1. Authentication (Mock)
app.post('/api/login', (req, res) => {
    const { email, password } = req.body;
    // Accept any login for demo
    if (email && password) {
        res.json({
            success: true,
            token: "mock_token_12345",
            user: {
                id: 1,
                firstName: "Demo",
                lastName: "User",
                email: email
            }
        });
    } else {
        res.status(400).json({ success: false, message: "Invalid credentials" });
    }
});

app.post('/api/signup', (req, res) => {
    const { email, password, firstName, lastName } = req.body;
    if (email && password && firstName && lastName) {
        res.json({
            success: true,
            token: "mock_token_67890",
            user: {
                id: 2,
                firstName,
                lastName,
                email
            }
        });
    } else {
        res.status(400).json({ success: false, message: "Missing fields" });
    }
});

// 2. Booking (Mock)
app.post('/api/book', (req, res) => {
    const { pickup, destination, vehicleType } = req.body;
    
    // Simulate processing delay
    setTimeout(() => {
        const randomDriver = drivers[Math.floor(Math.random() * drivers.length)];
        currentRideStatus = "driver_assigned"; // Reset status for new ride
        
        res.json({
            success: true,
            bookingId: "book_" + Date.now(),
            status: "driver_assigned",
            driver: randomDriver,
            eta: "5 mins",
            fare: 15.50 // Static fare for demo
        });
    }, 1000);
});

// 3. Ride Status (Simulation)
app.get('/api/ride-status', (req, res) => {
    // Simple state machine for demo purposes
    // In a real app, this would be based on driver location/updates
    
    // Cycle through states if called repeatedly or just return current state
    // For this demo, let's allow the client to "advance" state or just random?
    // Better: Time-based simulation or just return the current state and let client poll.
    // Let's make it advance every time it's called for easier demoing, OR just time based.
    // Let's go with a predictable sequence for the demo.
    
    // Sequence: driver_assigned -> driver_arrived -> in_progress -> completed
    
    if (currentRideStatus === "driver_assigned") {
        // 20% chance to move to next state
        if (Math.random() > 0.7) currentRideStatus = "driver_arrived";
    } else if (currentRideStatus === "driver_arrived") {
        if (Math.random() > 0.7) currentRideStatus = "in_progress";
    } else if (currentRideStatus === "in_progress") {
        if (Math.random() > 0.8) currentRideStatus = "completed";
    }
    
    res.json({
        status: currentRideStatus,
        location: { // Mock location updates could go here
            lat: 51.5074,
            lng: -0.1278
        }
    });
});

// Reset status endpoint for testing
app.post('/api/reset-ride', (req, res) => {
    currentRideStatus = "driver_assigned";
    res.json({ success: true, status: currentRideStatus });
});

app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});

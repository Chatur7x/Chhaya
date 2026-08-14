// Chaaya OnionNode Server
// A lightweight onion-routing packet forwarder that can be run on
// server nodes or self-hosted by private groups.
//
// This is the Go implementation of the Chaaya onion routing node.
// Each node peels one layer of encryption from incoming packets
// and forwards the inner payload to the next hop.

package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"
	"sync"
	"time"
)

// OnionPacket represents a multi-layered encrypted packet
type OnionPacket struct {
	PacketID    string    `json:"packet_id"`
	Payload     []byte    `json:"payload"`
	NextHop     string    `json:"next_hop"`
	LayersLeft  int       `json:"layers_left"`
	ReceivedAt  time.Time `json:"received_at"`
	TTLSeconds  int       `json:"ttl_seconds"`
}

// NodeConfig holds the configuration for this onion node
type NodeConfig struct {
	NodeID     string
	ListenAddr string
	PublicKey  []byte
	PrivateKey []byte
	MaxBuffer  int
}

// PacketStats tracks routing statistics
type PacketStats struct {
	mu              sync.RWMutex
	TotalReceived   uint64
	TotalForwarded  uint64
	TotalDropped    uint64
	TotalExpired    uint64
	AverageLatency  time.Duration
}

func (s *PacketStats) RecordReceived() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TotalReceived++
}

func (s *PacketStats) RecordForwarded() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TotalForwarded++
}

func (s *PacketStats) RecordDropped() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TotalDropped++
}

func (s *PacketStats) RecordExpired() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.TotalExpired++
}

func (s *PacketStats) Summary() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return fmt.Sprintf(
		"Received: %d | Forwarded: %d | Dropped: %d | Expired: %d",
		s.TotalReceived, s.TotalForwarded, s.TotalDropped, s.TotalExpired,
	)
}

// OnionNode is the main routing node
type OnionNode struct {
	Config  NodeConfig
	Stats   *PacketStats
	buffer  chan OnionPacket
	done    chan struct{}
}

// NewOnionNode creates and initializes a new onion routing node
func NewOnionNode(nodeID, listenAddr string) *OnionNode {
	// Generate simulated keypair
	pubKey := make([]byte, 32)
	privKey := make([]byte, 32)
	rand.Read(pubKey)
	rand.Read(privKey)

	return &OnionNode{
		Config: NodeConfig{
			NodeID:     nodeID,
			ListenAddr: listenAddr,
			PublicKey:  pubKey,
			PrivateKey: privKey,
			MaxBuffer:  1000,
		},
		Stats:  &PacketStats{},
		buffer: make(chan OnionPacket, 1000),
		done:   make(chan struct{}),
	}
}

// PeelLayer simulates removing one encryption layer from the packet
func (n *OnionNode) PeelLayer(packet OnionPacket) (*OnionPacket, error) {
	n.Stats.RecordReceived()

	// Check TTL
	elapsed := time.Since(packet.ReceivedAt)
	if elapsed > time.Duration(packet.TTLSeconds)*time.Second {
		n.Stats.RecordExpired()
		return nil, fmt.Errorf("packet %s expired (TTL: %ds, elapsed: %v)",
			packet.PacketID, packet.TTLSeconds, elapsed)
	}

	// Simulate decryption (peel one layer)
	if len(packet.Payload) < 32 {
		n.Stats.RecordDropped()
		return nil, fmt.Errorf("packet %s payload too small to peel", packet.PacketID)
	}

	// Hash the payload to simulate layer peeling
	hash := sha256.Sum256(packet.Payload)
	peeledPayload := hash[:]

	innerPacket := &OnionPacket{
		PacketID:   packet.PacketID,
		Payload:    peeledPayload,
		NextHop:    fmt.Sprintf("node_%s", hex.EncodeToString(peeledPayload[:4])),
		LayersLeft: packet.LayersLeft - 1,
		ReceivedAt: time.Now(),
		TTLSeconds: packet.TTLSeconds,
	}

	return innerPacket, nil
}

// ForwardPacket simulates forwarding the peeled packet to the next hop
func (n *OnionNode) ForwardPacket(packet *OnionPacket) error {
	if packet.LayersLeft <= 0 {
		// Final destination — deliver to recipient
		log.Printf("[DELIVER] Packet %s reached final destination", packet.PacketID)
		n.Stats.RecordForwarded()
		return nil
	}

	// Simulate network forwarding delay
	time.Sleep(50 * time.Millisecond)

	log.Printf("[FORWARD] Packet %s -> %s (%d layers remaining)",
		packet.PacketID, packet.NextHop, packet.LayersLeft)
	n.Stats.RecordForwarded()
	return nil
}

// ProcessQueue continuously processes incoming packets
func (n *OnionNode) ProcessQueue() {
	for {
		select {
		case packet := <-n.buffer:
			peeled, err := n.PeelLayer(packet)
			if err != nil {
				log.Printf("[DROP] %v", err)
				continue
			}
			if err := n.ForwardPacket(peeled); err != nil {
				log.Printf("[ERROR] Forward failed: %v", err)
			}
		case <-n.done:
			log.Println("[SHUTDOWN] Packet processor stopped")
			return
		}
	}
}

// InjectTestPacket creates and queues a test packet for processing
func (n *OnionNode) InjectTestPacket() {
	payload := make([]byte, 256)
	rand.Read(payload)

	idBytes := make([]byte, 8)
	rand.Read(idBytes)

	packet := OnionPacket{
		PacketID:   hex.EncodeToString(idBytes),
		Payload:    payload,
		NextHop:    n.Config.NodeID,
		LayersLeft: 3,
		ReceivedAt: time.Now(),
		TTLSeconds: 30,
	}

	n.buffer <- packet
}

// Stop gracefully shuts down the node
func (n *OnionNode) Stop() {
	close(n.done)
}

func main() {
	fmt.Println("╔══════════════════════════════════════════════════╗")
	fmt.Println("║         Chaaya OnionNode v2.0.0                 ║")
	fmt.Println("║  Lightweight Onion-Routing Packet Forwarder     ║")
	fmt.Println("╚══════════════════════════════════════════════════╝")
	fmt.Println()

	node := NewOnionNode("chaaya_node_alpha", ":8443")

	log.Printf("[INIT] Node ID: %s", node.Config.NodeID)
	log.Printf("[INIT] Public Key: %s", hex.EncodeToString(node.Config.PublicKey[:8]))
	log.Printf("[INIT] Listen Address: %s", node.Config.ListenAddr)
	log.Printf("[INIT] Buffer Size: %d packets", node.Config.MaxBuffer)
	fmt.Println()

	// Start packet processor
	go node.ProcessQueue()

	// Inject test packets
	log.Println("[TEST] Injecting 5 test packets...")
	for i := 0; i < 5; i++ {
		node.InjectTestPacket()
		time.Sleep(100 * time.Millisecond)
	}

	// Wait for processing
	time.Sleep(2 * time.Second)

	// Print stats
	fmt.Println()
	log.Printf("[STATS] %s", node.Stats.Summary())

	node.Stop()
	log.Println("[SHUTDOWN] Chaaya OnionNode stopped gracefully")
}

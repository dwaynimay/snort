from scapy.all import *
import urllib.parse

# konfigurasi
CLIENT_IP = "172.16.10.102"
SERVER_IP = "172.16.10.120"
SERVER_PORT = 80
BASE_CLIENT_PORT = 40000
OUT_PCAP = "sql_injection.pcap"

# list payload
SQLI_PAYLOADS = [
    "' OR '1'='1",
    "' OR 1=1--",
    "\" OR \"1\"=\"1",
    "admin'--",
    "1 OR 1=1",
    "1' OR '1'='1",
    "' OR 'a'='a",
    "') OR ('1'='1",
]

# generate one flow (three-way HS + HTTP + FIN)
def build_sqli_flow(payload, flow_id=0):
    packets = []
    client_port = BASE_CLIENT_PORT + flow_id
    # encode payload ke URL format
    encoded = urllib.parse.quote(payload)
    # sequence numbers
    client_seq = 1000 + flow_id * 1000
    server_seq = 5000 + flow_id * 2000
    # 1) SYN
    syn = IP(src=CLIENT_IP, dst=SERVER_IP)/TCP(sport=client_port,
                                               dport=SERVER_PORT, flags="S", seq=client_seq)
    packets.append(syn)
    # 2) SYN-ACK
    syn_ack = IP(src=SERVER_IP, dst=CLIENT_IP)/TCP(sport=SERVER_PORT,
                                                   dport=client_port, flags="SA", seq=server_seq, ack=client_seq+1)
    packets.append(syn_ack)
    # 3) ACK
    ack = IP(src=CLIENT_IP, dst=SERVER_IP)/TCP(sport=client_port,
                                               dport=SERVER_PORT, flags="A", seq=client_seq+1, ack=server_seq+1)
    packets.append(ack)
    # 4) HTTP GET dengan payload SQLi
    http_payload = (
        f"GET /test.php?id={encoded} HTTP/1.1\r\n"
        f"Host: {SERVER_IP}\r\n"
        "User-Agent: Scapy-SQLi-Generator\r\n"
        "Connection: close\r\n\r\n"
    )
    http_get = IP(src=CLIENT_IP, dst=SERVER_IP)/TCP(sport=client_port,
                                                    dport=SERVER_PORT, flags="PA", seq=client_seq+1, ack=server_seq+1)/http_payload
    packets.append(http_get)
    # 5) HTTP Response (dummy)
    http_response = IP(src=SERVER_IP, dst=CLIENT_IP)/TCP(sport=SERVER_PORT, dport=client_port, flags="PA", seq=server_seq+1, ack=client_seq+1+len(http_payload))/(
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html\r\n"
        "Content-Length: 7\r\n\r\nSuccess"
    )
    packets.append(http_response)
    # 6) FIN (client)
    fin = IP(src=CLIENT_IP, dst=SERVER_IP)/TCP(sport=client_port, dport=SERVER_PORT, flags="FA", seq=client_seq+1 +
                                               len(http_payload), ack=server_seq+1+len("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 7\r\n\r\nSuccess"))
    packets.append(fin)
    # 7) FIN-ACK (server)
    fin_ack = IP(src=SERVER_IP, dst=CLIENT_IP)/TCP(sport=SERVER_PORT,
                                                   dport=client_port, flags="FA", seq=server_seq+1+200, ack=fin.seq+1)
    packets.append(fin_ack)
    # 8) ACK final
    final_ack = IP(src=CLIENT_IP, dst=SERVER_IP)/TCP(sport=client_port,
                                                     dport=SERVER_PORT, flags="A", seq=fin.seq+1, ack=fin_ack.seq+1)
    packets.append(final_ack)

    return packets

# generate pcap semau payload
all_packets = []
for i, p in enumerate(SQLI_PAYLOADS):
    print(f"[+] Adding SQLi payload #{i}: {p}")
    all_packets += build_sqli_flow(p, flow_id=i)

# simpan pcap
wrpcap(OUT_PCAP, all_packets)
print(f"\n[✓] PCAP berhasil dibuat: {OUT_PCAP}")
print(f"[✓] Total packets: {len(all_packets)}")

package test

import (
        "time"
        "net"
				"strconv"
        "encoding/hex"
        "github.com/free5gc/CommonConsumerTestData/UDM/TestGenAuthData"
        "github.com/free5gc/nas"
        "github.com/free5gc/nas/nasMessage"
        "github.com/free5gc/nas/nasTestpacket"
        "github.com/free5gc/nas/nasType"
        "github.com/free5gc/nas/security"
        "github.com/free5gc/ngap"
        "github.com/free5gc/ngap/ngapType"
        "github.com/free5gc/openapi/models"
        "golang.org/x/net/icmp"
        "golang.org/x/net/ipv4"
				//"git.cs.nctu.edu.tw/calee/sctp"
				"log"
)

// Check for Error
func CheckErr(err error, msg string) {
	if err == nil {
		return
	}
	log.Fatalf("ERROR: %s: %s\n", msg, err)
}

// Get GetMobileIdentity5GS
func GetMobileIdentity5GS(imsi string) (uint64, uint64, uint64, uint64) {
  z := imsi[5:]
	a1 := z[0:2]
	b1 := z[2:4]
	c1 := z[4:6]
	d1 := z[6:8]
	a2 := string(a1[1])+string(a1[0])
	b2 := string(b1[1])+string(b1[0])
	c2 := string(c1[1])+string(c1[0])
	d2 := string(d1[1])+string(d1[0])
	a3, _ := strconv.ParseUint(a2, 16, 8)
	b3, _ := strconv.ParseUint(b2, 16, 8)
	c3, _ := strconv.ParseUint(c2, 16, 8)
	d3, _ := strconv.ParseUint(d2, 16, 8)

	return a3, b3, c3, d3
}

func RunRegTrans(imsiStr string, ranN2Ipv4Addr string, amfN2Ipv4Addr string, ranN3Ipv4Addr string, upfN3Ipv4Addr string) {
	var n int
	var sendMsg []byte
	var recvMsg = make([]byte, 2048)

	// RAN connect to AMF
	conn, err := ConnectToAmf(amfN2Ipv4Addr, ranN2Ipv4Addr, 38412, 9487)
	CheckErr(err, "ConnectToAmf")

	// RAN connect to UPF
	upfConn, err := ConnectToUpf(ranN3Ipv4Addr, upfN3Ipv4Addr, 2152, 2152)
	CheckErr(err, "ConnectToUpf")

	// send NGSetupRequest Msg
	sendMsg, err = GetNGSetupRequest([]byte("\x00\x01\x02"), 24, "free5gc")
	CheckErr(err, "GetNGSetupRequest")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "Write(sendMsg)")

	// receive NGSetupResponse Msg
	n, err = conn.Read(recvMsg)
	CheckErr(err, "Read(recvMsg)")
	ngapPdu, err := ngap.Decoder(recvMsg[:n])
	CheckErr(err, "ngap.Decoder")
	if ngapPdu.Present != ngapType.NGAPPDUPresentSuccessfulOutcome && ngapPdu.SuccessfulOutcome.ProcedureCode.Value != ngapType.ProcedureCodeNGSetup {
		log.Fatalf("No NGSetupResponse received.")
	}

	// New UE
	// ue := NewRanUeContext("imsi-2089300007487", 1, security.AlgCiphering128NEA2, security.AlgIntegrity128NIA2)
	ue := NewRanUeContext(string("imsi-")+string(imsiStr), 1, security.AlgCiphering128NEA0, security.AlgIntegrity128NIA2)
	ue.AmfUeNgapId = 1
	ue.AuthenticationSubs = GetAuthSubscription(TestGenAuthData.MilenageTestSet19.K,
		TestGenAuthData.MilenageTestSet19.OPC,
		TestGenAuthData.MilenageTestSet19.OP)
	// insert UE data to MongoDB

	servingPlmnId := "20893"
	InsertAuthSubscriptionToMongoDB(ue.Supi, ue.AuthenticationSubs)
	getData := GetAuthSubscriptionFromMongoDB(ue.Supi)
	if getData == nil {
		log.Fatalf("getData is nil - 1")
	}

	{
		amData := GetAccessAndMobilitySubscriptionData()
		InsertAccessAndMobilitySubscriptionDataToMongoDB(ue.Supi, amData, servingPlmnId)
		getData := GetAccessAndMobilitySubscriptionDataFromMongoDB(ue.Supi, servingPlmnId)
		if getData == nil {
			log.Fatalf("getData is nil - 2")
		}
	}
	{
		smfSelData := GetSmfSelectionSubscriptionData()
		InsertSmfSelectionSubscriptionDataToMongoDB(ue.Supi, smfSelData, servingPlmnId)
		getData := GetSmfSelectionSubscriptionDataFromMongoDB(ue.Supi, servingPlmnId)
		if getData == nil {
			log.Fatalf("getData is nil - 3")
		}
	}
	{
		smSelData := GetSessionManagementSubscriptionData()
		InsertSessionManagementSubscriptionDataToMongoDB(ue.Supi, servingPlmnId, smSelData)
		getData := GetSessionManagementDataFromMongoDB(ue.Supi, servingPlmnId)
		if getData == nil {
			log.Fatalf("getData is nil - 4")
		}
	}
	{
		amPolicyData := GetAmPolicyData()
		InsertAmPolicyDataToMongoDB(ue.Supi, amPolicyData)
		getData := GetAmPolicyDataFromMongoDB(ue.Supi)
		if getData == nil {
			log.Fatalf("getData is nil - 5")
		}
	}
	{
		smPolicyData := GetSmPolicyData()
		InsertSmPolicyDataToMongoDB(ue.Supi, smPolicyData)
		getData := GetSmPolicyDataFromMongoDB(ue.Supi)
		if getData == nil {
			log.Fatalf("getData is nil - 5")
		}
	}

  a3, b3, c3, d3 := GetMobileIdentity5GS(imsiStr)
	// send InitialUeMessage(Registration Request)(imsi-2089300007487)
	mobileIdentity5GS := nasType.MobileIdentity5GS{
		Len:    12, // suci
 		Buffer: []uint8{0x01, 0x02, 0xf8, 0x39, 0xf0, 0xff, 0x00, 0x00, uint8(a3), uint8(b3), uint8(c3), uint8(d3)},
	 }

	ueSecurityCapability := ue.GetUESecurityCapability()
	registrationRequest := nasTestpacket.GetRegistrationRequest(
		nasMessage.RegistrationType5GSInitialRegistration, mobileIdentity5GS, nil, ueSecurityCapability, nil, nil, nil)
	sendMsg, err = GetInitialUEMessage(ue.RanUeNgapId, registrationRequest, "")
	CheckErr(err, "GetInitialUEMessage")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// receive NAS Authentication Request Msg
	n, err = conn.Read(recvMsg)
	CheckErr(err, "conn.Read(recvMsg)")
	ngapPdu, err = ngap.Decoder(recvMsg[:n])
	CheckErr(err, "ngap.Decoder(recvMsg[:n])")
	if ngapPdu.Present != ngapType.NGAPPDUPresentInitiatingMessage {
		log.Fatalf("No NGAP Initiating Message received.")
	}

	// Calculate for RES*
	nasPdu := GetNasPdu(ue, ngapPdu.InitiatingMessage.Value.DownlinkNASTransport)
	if nasPdu == nil {
		log.Fatalf("nasPdu is nil")
	}
	if nasPdu.GmmMessage == nil {
		log.Fatalf("GMM message is nil")
	}
	if nasPdu.GmmHeader.GetMessageType() != nas.MsgTypeAuthenticationRequest {
		log.Fatalf("Received wrong GMM message. Expected Authentication Request.")
	}
	rand := nasPdu.AuthenticationRequest.GetRANDValue()
	resStat := ue.DeriveRESstarAndSetKey(ue.AuthenticationSubs, rand[:], "5G:mnc093.mcc208.3gppnetwork.org")

	// send NAS Authentication Response
	pdu := nasTestpacket.GetAuthenticationResponse(resStat, "")
	sendMsg, err = GetUplinkNASTransport(ue.AmfUeNgapId, ue.RanUeNgapId, pdu)
	CheckErr(err, "GetUplinkNASTransport")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// receive NAS Security Mode Command Msg
	n, err = conn.Read(recvMsg)
	CheckErr(err, "conn.Read(recvMsg)")
	ngapPdu, err = ngap.Decoder(recvMsg[:n])
	CheckErr(err, "ngap.Decoder(recvMsg[:n])")
	if ngapPdu == nil {
		log.Fatalf("ngapPdu is nil")
	}
	nasPdu = GetNasPdu(ue, ngapPdu.InitiatingMessage.Value.DownlinkNASTransport)
	if nasPdu == nil {
		log.Fatalf("nasPdu is nil")
	}
	if nasPdu.GmmMessage == nil {
		log.Fatalf("GMM message is nil")
	}
	if nasPdu.GmmHeader.GetMessageType() != nas.MsgTypeSecurityModeCommand {
		log.Fatalf("Received wrong GMM message. Expected Security Mode Command.")
	}

	// send NAS Security Mode Complete Msg
	registrationRequestWith5GMM := nasTestpacket.GetRegistrationRequest(nasMessage.RegistrationType5GSInitialRegistration,
		mobileIdentity5GS, nil, ueSecurityCapability, ue.Get5GMMCapability(), nil, nil)
	pdu = nasTestpacket.GetSecurityModeComplete(registrationRequestWith5GMM)
	pdu, err = EncodeNasPduWithSecurity(ue, pdu, nas.SecurityHeaderTypeIntegrityProtectedAndCipheredWithNew5gNasSecurityContext, true, true)
	CheckErr(err, "EncodeNasPduWithSecurity")
	sendMsg, err = GetUplinkNASTransport(ue.AmfUeNgapId, ue.RanUeNgapId, pdu)
	CheckErr(err, "GetUplinkNASTransport")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// receive ngap Initial Context Setup Request Msg
	n, err = conn.Read(recvMsg)
	CheckErr(err, "conn.Read(recvMsg)")
	ngapPdu, err = ngap.Decoder(recvMsg[:n])
	CheckErr(err, "ngap.Decoder(recvMsg[:n])")
	if ngapPdu.Present != ngapType.NGAPPDUPresentInitiatingMessage && ngapPdu.InitiatingMessage.ProcedureCode.Value != ngapType.ProcedureCodeInitialContextSetup {
		log.Fatalf("No InitialContextSetup received.")
	}

	// send ngap Initial Context Setup Response Msg
	sendMsg, err = GetInitialContextSetupResponse(ue.AmfUeNgapId, ue.RanUeNgapId)
	CheckErr(err, "GetInitialContextSetupResponse")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// send NAS Registration Complete Msg
	pdu = nasTestpacket.GetRegistrationComplete(nil)
	pdu, err = EncodeNasPduWithSecurity(ue, pdu, nas.SecurityHeaderTypeIntegrityProtectedAndCiphered, true, false)
	CheckErr(err, "EncodeNasPduWithSecurity")
	sendMsg, err = GetUplinkNASTransport(ue.AmfUeNgapId, ue.RanUeNgapId, pdu)
	CheckErr(err, "GetUplinkNASTransport")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	time.Sleep(100 * time.Millisecond)
	// send GetPduSessionEstablishmentRequest Msg

	sNssai := models.Snssai{
		Sst: 1,
		Sd:  "010203",
	}
	pdu = nasTestpacket.GetUlNasTransport_PduSessionEstablishmentRequest(10, nasMessage.ULNASTransportRequestTypeInitialRequest, "internet", &sNssai)
	pdu, err = EncodeNasPduWithSecurity(ue, pdu, nas.SecurityHeaderTypeIntegrityProtectedAndCiphered, true, false)
	CheckErr(err, "EncodeNasPduWithSecurity")
	sendMsg, err = GetUplinkNASTransport(ue.AmfUeNgapId, ue.RanUeNgapId, pdu)
	CheckErr(err, "GetUplinkNASTransport")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// receive 12. NGAP-PDU Session Resource Setup Request(DL nas transport((NAS msg-PDU session setup Accept)))
	n, err = conn.Read(recvMsg)
	CheckErr(err, "conn.Read(recvMsg)")
	ngapPdu, err = ngap.Decoder(recvMsg[:n])
	CheckErr(err, "ngap.Decoder(recvMsg[:n])")

  if ngapPdu.Present != ngapType.NGAPPDUPresentInitiatingMessage && ngapPdu.InitiatingMessage.ProcedureCode.Value != ngapType.ProcedureCodePDUSessionResourceSetup {
		log.Fatalf("No PDUSessionResourceSetup received.")
	}

	// send 14. NGAP-PDU Session Resource Setup Response
	sendMsg, err = GetPDUSessionResourceSetupResponse(10, ue.AmfUeNgapId, ue.RanUeNgapId, ranN3Ipv4Addr)
	CheckErr(err, "GetPDUSessionResourceSetupResponse")
	_, err = conn.Write(sendMsg)
	CheckErr(err, "conn.Write(sendMsg)")

	// wait 1s
	time.Sleep(1 * time.Second)

	// Send the dummy packet
	// ping IP(tunnel IP) from 60.60.0.2(127.0.0.1) to 60.60.0.20(127.0.0.8)
	gtpHdr, err := hex.DecodeString("32ff00340000000100000000")
	CheckErr(err, "hex.DecodeString - 1")
	icmpData, err := hex.DecodeString("8c870d0000000000101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f3031323334353637")
	CheckErr(err, "hex.DecodeString - 2")

	ipv4hdr := ipv4.Header{
		Version:  4,
		Len:      20,
		Protocol: 1,
		Flags:    0,
		TotalLen: 48,
		TTL:      64,
		Src:      net.ParseIP("60.60.0.1").To4(),
		Dst:      net.ParseIP("60.60.0.101").To4(),
		ID:       1,
	}
	checksum := CalculateIpv4HeaderChecksum(&ipv4hdr)
	ipv4hdr.Checksum = int(checksum)

	v4HdrBuf, err := ipv4hdr.Marshal()
	CheckErr(err, "ipv4hdr.Marshal()")
	tt := append(gtpHdr, v4HdrBuf...)

	m := icmp.Message{
		Type: ipv4.ICMPTypeEcho, Code: 0,
		Body: &icmp.Echo{
			ID: 12394, Seq: 1,
			Data: icmpData,
		},
	}
	b, err := m.Marshal(nil)
	CheckErr(err, "m.Marshal(nil)")
	b[2] = 0xaf
	b[3] = 0x88
	_, err = upfConn.Write(append(tt, b...))
	CheckErr(err, "upfConn.Write")

	time.Sleep(1 * time.Second)

	// delete test data
	DelAuthSubscriptionToMongoDB(ue.Supi)
	DelAccessAndMobilitySubscriptionDataFromMongoDB(ue.Supi, servingPlmnId)
	DelSmfSelectionSubscriptionDataFromMongoDB(ue.Supi, servingPlmnId)

	// close Connection
	conn.Close()
	upfConn.Close()

	// terminate all NF
	//NfTerminate()
}

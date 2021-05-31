package main

import (
  "test"
	"strconv"
	"log"
	"fmt"
	"io/ioutil"
)

var enableLogging = true

func main() {
	if !enableLogging {
		fmt.Printf("Logging is disabled")
		log.SetOutput(ioutil.Discard)
	}

	imsi := 2089300000000
  servingPlmnId := "20893"
	for i := 0; i < 10; i++ {
		fmt.Printf("Loop %d", i)
		fmt.Println("")
    // delete test data
    imsiStr := string("imsi-")+string(strconv.Itoa(imsi))
  	test.DelAuthSubscriptionToMongoDB(imsiStr)
  	test.DelAccessAndMobilitySubscriptionDataFromMongoDB(imsiStr, servingPlmnId)
    test.DelSessionManagementSubscriptionDataFromMongoDB(imsiStr, servingPlmnId)
  	test.DelSmfSelectionSubscriptionDataFromMongoDB(imsiStr, servingPlmnId)
    test.DelAmPolicyDataFromMongoDB(imsiStr)
    test.DelSmPolicyDataFromMongoDB(imsiStr)
		imsi = imsi + 1
	}

}

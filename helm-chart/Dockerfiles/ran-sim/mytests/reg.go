package main

import (
        "test"
				"strconv"
				"log"
				"fmt"
				"io/ioutil"
)

const ranN2Ipv4Addr string = "10.244.1.3"
const amfN2Ipv4Addr string = "10.244.1.2"
const ranN3Ipv4Addr string = "10.244.1.3"
const upfN3Ipv4Addr string = "10.244.1.8"
var enableLogging = true

func main() {
	if !enableLogging {
		fmt.Printf("Logging is disabled")
		log.SetOutput(ioutil.Discard)
	}

	imsi := 2089300000000
	for i := 0; i < 1; i++ {
		fmt.Printf("Loop %d", i)
		fmt.Println("")
		test.RunRegTrans(strconv.Itoa(imsi), ranN2Ipv4Addr, amfN2Ipv4Addr, ranN3Ipv4Addr, upfN3Ipv4Addr)
		imsi = imsi + 1
	}

}

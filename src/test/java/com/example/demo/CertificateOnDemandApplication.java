package com.example.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Sample application to showcase SSL Certificate on Demand.
 *
 * @author Mark Paluch
 */
@SpringBootApplication
public class CertificateOnDemandApplication {

	public static void main(String[] args) {
		SpringApplication.run(CertificateOnDemandApplication.class);
	}

	@RestController
	static class HelloWorld {

		@GetMapping(path = "/")
		ResponseEntity<String> hello() {
			return ResponseEntity.ok("Hello, World");
		}
	}

}
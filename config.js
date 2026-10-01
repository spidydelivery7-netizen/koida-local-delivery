window.SPIDY_CONFIG = {
  businessName: "HUNKART STAGING",
  whatsappNumber: "",
  supabaseUrl: "https://jjitqihblpubqwbggjpv.supabase.co",
  supabaseAnonKey: "sb_publishable_RxMB6BPXWcEnmmHCFFa_Bg_arV4t45w",
  onlinePaymentEnabled: true,
  razorpayKeyId: "",
  stagingMode: true
};

const stagingFetch = window.fetch.bind(window);
window.fetch = function (input, options) {
  const url = new URL(
    typeof input === "string" ? input : input.url,
    window.location.href
  );

  if (url.hostname.endsWith(".supabase.co") &&
      url.hostname !== "jjitqihblpubqwbggjpv.supabase.co") {
    return Promise.reject(new Error("Live Supabase blocked on staging"));
  }

  if (url.hostname === "jjitqihblpubqwbggjpv.supabase.co" &&
      (url.pathname.startsWith("/functions/v1/") ||
       /^\/rest\/v1\/rpc\/(place_order|place_paid_order)$/.test(url.pathname))) {
    return Promise.reject(new Error("Checkout disabled on staging"));
  }

  return stagingFetch(input, options);
};

document.addEventListener("click", function (event) {
  if (event.target.closest?.("#placeOrder, #payNow, #rideBookLink")) {
    event.preventDefault();
    event.stopImmediatePropagation();
    alert("Checkout disabled on staging.");
  }
}, true);

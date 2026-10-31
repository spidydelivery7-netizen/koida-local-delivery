const hunkartPreviewHost = location.hostname === "deploy-preview-1--cheery-marshmallow-1e366d.netlify.app"
  || location.hostname.endsWith(".koida-local-delivery.pages.dev")
  || (location.hostname.endsWith(".workers.dev")
    && location.hostname !== "koida-local-delivery.spidydelivery7.workers.dev");
window.SPIDY_CONFIG = hunkartPreviewHost ? {
  businessName: "HUNKART STAGING",
  whatsappNumber: "918638794932",
  supabaseUrl: "https://jjitqihblpubqwbggjpv.supabase.co",
  supabaseAnonKey: "sb_publishable_RxMB6BPXWcEnmmHCFFa_Bg_arV4t45w",
  onlinePaymentEnabled: false,
  razorpayKeyId: ""
} : {
  businessName: "Koida Local Delivery",
  whatsappNumber: "918638794932",
  supabaseUrl: "https://amnqqxgmqciipcortpmi.supabase.co",
  supabaseAnonKey: "sb_publishable_IfYta_zgbZSgoIUS0hsA1w_eRLLAQjk",
  onlinePaymentEnabled: true,
  razorpayKeyId: ""
};

package id.laskarmedia.openvpn_flutter;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.VpnService;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.ArrayList;

import de.blinkt.openvpn.OnVPNStatusChangeListener;
import de.blinkt.openvpn.VPNHelper;
import de.blinkt.openvpn.core.OpenVPNService;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * OpenvpnFlutterPlugin
 */
public class OpenVPNFlutterPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener {

    private MethodChannel vpnControlMethod;
    private EventChannel vpnStageEvent;
    //    private EventChannel vpnStatusEvent;
    private EventChannel.EventSink vpnStageSink;
//    private EventChannel.EventSink vpnStatusSink;

    private static final String EVENT_CHANNEL_VPN_STAGE = "id.laskarmedia.openvpn_flutter/vpnstage";
    //    private static final String EVENT_CHANNEL_VPN_STATUS = "id.laskarmedia.openvpn_flutter/vpnstatus";
    private static final String METHOD_CHANNEL_VPN_CONTROL = "id.laskarmedia.openvpn_flutter/vpncontrol";

    private static String config = "", username = "", password = "", name = "";
    private static Boolean isKillSwitchEnabled = false;

    private static ArrayList<String> bypassPackages;
    @SuppressLint("StaticFieldLeak")
    private static VPNHelper vpnHelper;
    private Activity activity;

    Context mContext;

    static MethodChannel.Result result;

    // set result
    public static void setResult(MethodChannel.Result methodChannelResult) {
        result = methodChannelResult;
    }

    public static void connectWhileGranted(boolean granted) {
        if (result != null) {
            result.success(granted);
        }

        if (granted && vpnHelper != null && config != null && !config.isEmpty()) {
            vpnHelper.startVPN(config, username, password, name, bypassPackages, isKillSwitchEnabled);
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        vpnStageEvent = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL_VPN_STAGE);
        vpnControlMethod = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL_VPN_CONTROL);

        vpnStageEvent.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                vpnStageSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                if (vpnStageSink != null) vpnStageSink.endOfStream();
            }
        });

        vpnControlMethod.setMethodCallHandler((call, result) -> {
            setResult(result);

            switch (call.method) {
                case "applyKillSwitch":
                    if (vpnHelper == null) {
                        result.error("-1", "VPNEngine needs to be initialized", "");
                        return;
                    }
                    vpnHelper.applyKillSwitch();
                    result.success(true);
                    break;

                case "removeKillSwitch":
                    if (vpnHelper == null) {
                        result.error("-1", "VPNEngine needs to be initialized", "");
                        return;
                    }
                    vpnHelper.removeKillSwitch();
                    result.success(true);
                    break;
                case "status":
                    if (vpnHelper == null) {
                        result.error("-1", "VPNEngine need to be initialize", "");
                        return;
                    }
                    result.success(vpnHelper.status.toString());
                    break;
                case "initialize":
                    vpnHelper = new VPNHelper(activity);
                    vpnHelper.setOnVPNStatusChangeListener(new OnVPNStatusChangeListener() {
                        @Override
                        public void onVPNStatusChanged(String status) {
                            updateStage(status);
                        }

                        @Override
                        public void onConnectionStatusChanged(String duration, String lastPacketReceive, String byteIn, String byteOut) {

                        }
                    });
                    result.success(updateVPNStages());
                    break;
                case "disconnect":
                    if (vpnHelper == null)
                        result.error("-1", "VPNEngine need to be initialize", "");

                    
                    Boolean applyKillSwitch = call.argument("apply_kill_switch");
                    if (applyKillSwitch == null) {
                        applyKillSwitch = false;
                    }

                    vpnHelper.stopVPN(applyKillSwitch);
                    updateStage("disconnected");
                    break;
                case "connect":
                    if (vpnHelper == null) {
                        result.error("-1", "VPNEngine need to be initialize", "");
                        return;
                    }

                    config = call.argument("config");
                    name = call.argument("name");
                    username = call.argument("username");
                    password = call.argument("password");
                    bypassPackages = call.argument("bypass_packages");
                    isKillSwitchEnabled = call.argument("is_kill_switch_enabled");
                    if (isKillSwitchEnabled == null) {
                        isKillSwitchEnabled = false;
                    }

                    if (config == null) {
                        result.error("-2", "OpenVPN Config is required", "");
                        return;
                    }

                    final Intent permission = VpnService.prepare(activity);
                    if (permission != null) {
                        activity.startActivityForResult(permission, 24);
                        return;
                    }
                    vpnHelper.startVPN(config, username, password, name, bypassPackages, isKillSwitchEnabled);
                    break;
                case "stage":
                    if (vpnHelper == null) {
                        result.error("-1", "VPNEngine need to be initialize", "");
                        return;
                    }
                    result.success(updateVPNStages());
                    break;
                case "request_permission":
                    final Intent request = VpnService.prepare(activity);
                    if (request != null) {
                        activity.startActivityForResult(request, 24);
                        return;
                    }
                    result.success(true);
                    break;
                case "check_permission":
                    final Intent checkPermission = VpnService.prepare(activity);
                    if (checkPermission != null) {
                        result.success(false);
                        return;
                    }
                    result.success(true);
                    break;
                default:
            }
        });
        mContext = binding.getApplicationContext();
    }

    public void updateStage(String stage) {
        if (stage == null) stage = "idle";
        if (vpnStageSink != null) vpnStageSink.success(stage.toLowerCase());
    }


    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        vpnStageEvent.setStreamHandler(null);
        vpnControlMethod.setMethodCallHandler(null);
//        vpnStatusEvent.setStreamHandler(null);
    }


    private String updateVPNStages() {
        if (OpenVPNService.getStatus() == null) {
            OpenVPNService.setDefaultStatus();
        }
        updateStage(OpenVPNService.getStatus());
        return OpenVPNService.getStatus();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {

    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode == 24) {
            if (result != null && resultCode == Activity.RESULT_OK) {
                result.success(true);
                return true;
            } else if (result != null) {
                result.success(false);
            }
        }

        return false;
    }
}
